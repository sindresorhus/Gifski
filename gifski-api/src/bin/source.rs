use crate::BinResult;
use gifski::Collector;

pub trait Source: Send {
    fn total_frames(&self) -> Option<u64>;
    fn collect(&mut self, dest: &mut Collector) -> BinResult<()>;
}

#[derive(Debug, Copy, Clone)]
pub struct Fps {
    /// output rate
    pub fps: f32,
    /// skip frames
    pub speed: f32,
}
