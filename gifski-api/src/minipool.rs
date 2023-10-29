use std::num::NonZeroU8;
use std::panic::catch_unwind;
use std::sync::atomic::{AtomicBool, Ordering::Relaxed};
use crossbeam_channel::Sender;
use crate::Error;

#[inline]
pub fn new_channel<P, C, M, R>(num_threads: NonZeroU8, name: &str, producer: P, mut consumer: C) -> Result<R, Error> where
    M: Send,
    C: Clone + Send + FnMut(M) -> Result<(), Error> + std::panic::UnwindSafe,
    P: FnOnce(Sender<M>) -> Result<R, Error>,
{
    let (s, r) = crossbeam_channel::bounded(2);
    new_scope(num_threads, name, move || producer(s),
        move |should_abort| {
            for m in r {
                if should_abort.load(Relaxed) {
                    break;
                }
                consumer(m)?;
            }
            Ok(())
        })
}

pub fn new_scope<P, C, R>(num_threads: NonZeroU8, name: &str, waiter: P, consumer: C) -> Result<R, Error> where
    C: Clone + Send + FnOnce(&AtomicBool) -> Result<(), Error> + std::panic::UnwindSafe,
    P: FnOnce() -> Result<R, Error>,
{
    let failed = &AtomicBool::new(false);
    std::thread::scope(move |scope| {
        let thread = move || {
            catch_unwind(move || consumer(failed))
                .map_err(|_| Error::ThreadSend).and_then(|x| x)
                .map_err(|e| {
                    failed.store(true, Relaxed);
                    e
                })
        };
        let handles = std::iter::repeat(thread).enumerate()
            .take(num_threads.get().into())
            .map(move |(n, thread)| {
                std::thread::Builder::new().name(format!("{name}{n}")).spawn_scoped(scope, thread)
            })
            .collect::<Result<Vec<_>, _>>()
            .map_err(move |_| {
                failed.store(true, Relaxed);
                Error::ThreadSend
            })?;

        let res = waiter().map_err(|e| {
            failed.store(true, Relaxed);
            e
        });
        handles.into_iter().try_for_each(|h| h.join().map_err(|_| Error::ThreadSend)?)?;
        res
    })
}
