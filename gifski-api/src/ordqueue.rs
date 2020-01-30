use crate::error::*;
use std::cmp::Ordering;
use std::collections::BinaryHeap;
use std::sync::mpsc;

pub struct OrdQueue<T> {
    sender: mpsc::SyncSender<ReverseTuple<T>>,
}

pub struct OrdQueueIter<T> {
    receiver: mpsc::Receiver<ReverseTuple<T>>,
    next_index: usize,
    receive_buffer: BinaryHeap<ReverseTuple<T>>,
}

pub fn new<T>(depth: usize) -> (OrdQueue<T>, OrdQueueIter<T>) {
    let (sender, receiver) = mpsc::sync_channel(depth);
    (OrdQueue {
        sender,
    }, OrdQueueIter {
        receiver,
        next_index: 0,
        receive_buffer: BinaryHeap::new()
    })
}

impl<T: Send + 'static> OrdQueue<T> {
    pub fn push(&mut self, index: usize, item: T) -> CatResult<()> {
        self.sender.send(ReverseTuple(index, item)).map_err(|_| ErrorKind::ThreadSend)?;
        Ok(())
    }
}

impl<T> Iterator for OrdQueueIter<T> {
    type Item = T;
    fn next(&mut self) -> Option<T> {
        while self.receive_buffer.peek().map(|i| i.0) != Some(self.next_index) {
            match self.receiver.recv() {
                Ok(item) => {
                    self.receive_buffer.push(item);
                },
                Err(_) => {
                    // Sender dropped (but continue to dump receive_buffer buffer)
                    break;
                },
            }
        }

        if let Some(item) = self.receive_buffer.pop() {
            self.next_index += 1;
            Some(item.1)
        } else {
            None
        }
    }
}

struct ReverseTuple<T>(usize, T);
impl<T> PartialEq for ReverseTuple<T> {
    fn eq(&self, o: &Self) -> bool { o.0.eq(&self.0) }
}
impl<T> Eq for ReverseTuple<T> {}
impl<T> PartialOrd for ReverseTuple<T> {
    fn partial_cmp(&self, o: &Self) -> Option<Ordering> { o.0.partial_cmp(&self.0) }
}
impl<T> Ord for ReverseTuple<T> {
    fn cmp(&self, o: &Self) -> Ordering { o.0.cmp(&self.0) }
}
