use gifski::Collector;
use crate::error::*;

pub trait Source: Send {
    fn total_frames(&self) -> u64;
    fn collect(&mut self, dest: Collector) -> BinResult<()>;
}
