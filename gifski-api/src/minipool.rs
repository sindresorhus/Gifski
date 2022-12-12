use std::panic::catch_unwind;
use std::sync::atomic::{AtomicBool, Ordering::SeqCst};
use crossbeam_channel::Sender;
use crate::Error;

pub fn new<P, C, M, R>(num_threads: u8, name: &str, producer: P, mut consumer: C) -> Result<R, Error> where
    M: Send,
    C: Clone + Send + FnMut(M) -> Result<(), Error> + std::panic::UnwindSafe,
    P: FnOnce(Sender<M>) -> Result<R, Error>,
{
    let failed = &AtomicBool::new(false);
    std::thread::scope(move |scope| {
        let (s, r) = crossbeam_channel::bounded(2);
        let thread = move || {
            catch_unwind(move || {
                for m in r {
                    if failed.load(SeqCst) {
                        break;
                    }
                    if let Err(e) = consumer(m) {
                        failed.store(true, SeqCst);
                        return Err(e);
                    }
                }
                Ok(())
            }).map_err(move |_| {
                failed.store(true, SeqCst);
                Error::ThreadSend
            })?
        };
        let spawn = move |n, thread| {
            std::thread::Builder::new().name(format!("{name}{n}")).spawn_scoped(scope, thread).map_err(|_| {
                failed.store(true, SeqCst);
                Error::ThreadSend
            })
        };
        debug_assert!(num_threads > 0);
        let mut handles = Vec::with_capacity(num_threads.into());
        for n in 0..num_threads-1 {
            handles.push(spawn(n, thread.clone())?);
        }
        handles.push(spawn(num_threads-1, thread)?);

        let res = producer(s).map_err(|e| {
            failed.store(true, SeqCst);
            e
        });
        handles.into_iter().try_for_each(|h| h.join().map_err(|_| Error::ThreadSend)?)?;
        res
    })
}
