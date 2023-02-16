#include <stdarg.h>
#include <stdint.h>
#include <stdlib.h>
#include <stdbool.h>


#ifdef __cplusplus
extern "C" {
#endif

struct gifski;
typedef struct gifski gifski;

/**
How to use from C

```c
gifski *g = gifski_new(&(GifskiSettings){
  .quality = 90,
});
gifski_set_file_output(g, "file.gif");

for(int i=0; i < frames; i++) {
     int res = gifski_add_frame_rgba(g, i, width, height, buffer, 5);
     if (res != GIFSKI_OK) break;
}
int res = gifski_finish(g);
if (res != GIFSKI_OK) return;
```

It's safe and efficient to call `gifski_add_frame_*` in a loop as fast as you can get frames,
because it blocks and waits until previous frames are written.

To cancel processing, make progress callback return 0 and call `gifski_finish()`. The write callback
may still be called between the cancellation and `gifski_finish()` returning.

To build as a library:

```bash
cargo build --release --lib
```

it will create `target/release/libgifski.a` (static library)
and `target/release/libgifski.so`/`dylib` or `gifski.dll` (dynamic library)

Static is recommended.

To build for iOS:

```bash
rustup target add aarch64-apple-ios
cargo build --release --lib --target aarch64-apple-ios
```

it will build `target/aarch64-apple-ios/release/libgifski.a` (ignore the warning about cdylib).

*/

/**
 * Settings for creating a new encoder instance. See `gifski_new`
 */
typedef struct GifskiSettings {
  /**
   * Resize to max this width if non-0.
   */
  uint32_t width;
  /**
   * Resize to max this height if width is non-0. Note that aspect ratio is not preserved.
   */
  uint32_t height;
  /**
   * 1-100, but useful range is 50-100. Recommended to set to 90.
   */
  uint8_t quality;
  /**
   * Lower quality, but faster encode.
   */
  bool fast;
  /**
   * If negative, looping is disabled. The number of times the sequence is repeated. 0 to loop forever.
   */
  int16_t repeat;
} GifskiSettings;

enum GifskiError {
  GIFSKI_OK = 0,
  /** one of input arguments was NULL */
  GIFSKI_NULL_ARG,
  /** a one-time function was called twice, or functions were called in wrong order */
  GIFSKI_INVALID_STATE,
  /** internal error related to palette quantization */
  GIFSKI_QUANT,
  /** internal error related to gif composing */
  GIFSKI_GIF,
  /** internal error - unexpectedly aborted */
  GIFSKI_THREAD_LOST,
  /** I/O error: file or directory not found */
  GIFSKI_NOT_FOUND,
  /** I/O error: permission denied */
  GIFSKI_PERMISSION_DENIED,
  /** I/O error: file already exists */
  GIFSKI_ALREADY_EXISTS,
  /** invalid arguments passed to function */
  GIFSKI_INVALID_INPUT,
  /** misc I/O error */
  GIFSKI_TIMED_OUT,
  /** misc I/O error */
  GIFSKI_WRITE_ZERO,
  /** misc I/O error */
  GIFSKI_INTERRUPTED,
  /** misc I/O error */
  GIFSKI_UNEXPECTED_EOF,
  /** progress callback returned 0, writing aborted */
  GIFSKI_ABORTED,
  /** should not happen, file a bug */
  GIFSKI_OTHER,
};

/* workaround for a wrong definition in an older version of this header. Please use GIFSKI_ABORTED directly */
#ifndef ABORTED
#define ABORTED GIFSKI_ABORTED
#endif

typedef enum GifskiError GifskiError;

/**
 * Call to start the process
 *
 * See `gifski_add_frame_png_file` and `gifski_end_adding_frames`
 *
 * Returns a handle for the other functions, or `NULL` on error (if the settings are invalid).
 */
gifski *gifski_new(const GifskiSettings *settings);


/** Quality 1-100 of temporal denoising. Lower values reduce motion. Defaults to `settings.quality`.
 *
 * Only valid immediately after calling `gifski_new`, before any frames are added. */
GifskiError gifski_set_motion_quality(gifski *handle, uint8_t quality);

/** Quality 1-100 of gifsicle compression. Lower values add noise. Defaults to `settings.quality`.
 * Has no effect if the `gifsicle` feature hasn't been enabled.
 * Only valid immediately after calling `gifski_new`, before any frames are added. */
GifskiError gifski_set_lossy_quality(gifski *handle, uint8_t quality);

/** If `true`, encoding will be significantly slower, but may look a bit better.
 *
 * Only valid immediately after calling `gifski_new`, before any frames are added. */
GifskiError gifski_set_extra_effort(gifski *handle, bool extra);

/**
 * Adds a frame to the animation. This function is asynchronous.
 *
 * File path must be valid UTF-8.
 *
 * `frame_number` orders frames (consecutive numbers starting from 0).
 * You can add frames in any order, and they will be sorted by their `frame_number`.
 *
 * Presentation timestamp (PTS) is time in seconds, since start of the file, when this frame is to be displayed.
 * For a 20fps video it could be `frame_number/20.0`.
 * Frames with duplicate or out-of-order PTS will be skipped.
 *
 * The first frame should have PTS=0. If the first frame has PTS > 0, it'll be used as a delay after the last frame.
 *
 * Returns 0 (`GIFSKI_OK`) on success, and non-0 `GIFSKI_*` constant on error.
 */
GifskiError gifski_add_frame_png_file(gifski *handle,
                                      uint32_t frame_number,
                                      const char *file_path,
                                      double presentation_timestamp);

/**
 * Adds a frame to the animation. This function is asynchronous.
 *
 * `pixels` is an array width×height×4 bytes large.
 * The array is copied, so you can free/reuse it immediately after this function returns.
 *
 * `frame_number` orders frames (consecutive numbers starting from 0).
 * You can add frames in any order, and they will be sorted by their `frame_number`.
 *
 * Presentation timestamp (PTS) is time in seconds, since start of the file, when this frame is to be displayed.
 * For a 20fps video it could be `frame_number/20.0`. First frame must have PTS=0.
 * Frames with duplicate or out-of-order PTS will be skipped.
 *
 * The first frame should have PTS=0. If the first frame has PTS > 0, it'll be used as a delay after the last frame.
 *
 * Colors are in sRGB, uncorrelated RGBA, with alpha byte last.
 *
 * Returns 0 (`GIFSKI_OK`) on success, and non-0 `GIFSKI_*` constant on error.
 */
GifskiError gifski_add_frame_rgba(gifski *handle,
                                  uint32_t frame_number,
                                  uint32_t width,
                                  uint32_t height,
                                  const unsigned char *pixels,
                                  double presentation_timestamp);

/** Same as `gifski_add_frame_rgba`, but with bytes per row arg */
GifskiError gifski_add_frame_rgba_stride(gifski *handle,
                                  uint32_t frame_number,
                                  uint32_t width,
                                  uint32_t height,
                                  uint32_t bytes_per_row,
                                  const unsigned char *pixels,
                                  double presentation_timestamp);

/** Same as `gifski_add_frame_rgba_stride`, except it expects components in ARGB order.

Bytes per row must be multiple of 4, and greater or equal width×4.
If the bytes per row value is invalid (e.g. an odd number), frames may look sheared/skewed.

Colors are in sRGB, uncorrelated ARGB, with alpha byte first.

`gifski_add_frame_rgba` is preferred over this function.
*/
GifskiError gifski_add_frame_argb(gifski *handle,
                                  uint32_t frame_number,
                                  uint32_t width,
                                  uint32_t bytes_per_row,
                                  uint32_t height,
                                  const unsigned char *pixels,
                                  double presentation_timestamp);

/** Same as `gifski_add_frame_rgba_stride`, except it expects RGB components (3 bytes per pixel)

Bytes per row must be multiple of 3, and greater or equal width×3.
If the bytes per row value is invalid (not multiple of 3), frames may look sheared/skewed.

Colors are in sRGB, red byte first.

`gifski_add_frame_rgba` is preferred over this function.
*/
GifskiError gifski_add_frame_rgb(gifski *handle,
                                 uint32_t frame_number,
                                 uint32_t width,
                                 uint32_t bytes_per_row,
                                 uint32_t height,
                                 const unsigned char *pixels,
                                 double presentation_timestamp);

/**
 * Get a callback for frame processed, and abort processing if desired.
 *
 * The callback is called once per input frame,
 * even if the encoder decides to skip some frames.
 *
 * It gets arbitrary pointer (`user_data`) as an argument. `user_data` can be `NULL`.
 *
 * The callback must return `1` to continue processing, or `0` to abort.
 *
 * The callback must be thread-safe (it will be called from another thread).
 * It must remain valid at all times, until `gifski_finish` completes.
 *
 * This function must be called before `gifski_set_file_output()` to take effect.
 */
void gifski_set_progress_callback(gifski *handle, int (*progress_callback)(void *user_data), void *user_data);

/**
 * Get a callback when an error occurs.
 * This is intended mostly for logging and debugging, not for user interface.
 *
 * The callback function has the following arguments:
 *  * A `\0`-terminated C string in UTF-8 encoding. The string is only valid for the duration of the call. Make a copy if you need to keep it.
 *  * An arbitrary pointer (`user_data`). `user_data` can be `NULL`.
 *
 * The callback must be thread-safe (it will be called from another thread).
 * It must remain valid at all times, until `gifski_finish` completes.
 *
 * If the callback is not set, errors will be printed to stderr.
 *
 * This function must be called before `gifski_set_file_output()` to take effect.
 */
GifskiError gifski_set_error_message_callback(gifski *handle, void (*error_message_callback)(const char*, void*), void *user_data);

/**
 * Start writing to the file at `destination_path` (overwrites if needed).
 * The file path must be ASCII or valid UTF-8.
 *
 * This function has to be called before any frames are added.
 * This call will not block.
 *
 * Returns 0 (`GIFSKI_OK`) on success, and non-0 `GIFSKI_*` constant on error.
 */
GifskiError gifski_set_file_output(gifski *handle, const char *destination_path);

/**
 * Start writing via callback (any buffer, file, whatever you want). This has to be called before any frames are added.
 * This call will not block.
 *
 * The callback function receives 3 arguments:
 *  - size of the buffer to write, in bytes. IT MAY BE ZERO (when it's zero, either do nothing, or flush internal buffers if necessary).
 *  - pointer to the buffer.
 *  - context pointer to arbitrary user data, same as passed in to this function.
 *
 * The callback should return 0 (`GIFSKI_OK`) on success, and non-zero on error.
 *
 * The callback function must be thread-safe. It must remain valid at all times, until `gifski_finish` completes.
 *
 * Returns 0 (`GIFSKI_OK`) on success, and non-0 `GIFSKI_*` constant on error.
 */
GifskiError gifski_set_write_callback(gifski *handle,
                                      int (*write_callback)(size_t buffer_length, const uint8_t *buffer, void *user_data),
                                      void *user_data);

/**
 * The last step:
 *  - stops accepting any more frames (gifski_add_frame_* calls are blocked)
 *  - blocks and waits until all already-added frames have finished writing
 *
 * Returns final status of write operations. Remember to check the return value!
 *
 * Must always be called, otherwise it will leak memory.
 * After this call, the handle is freed and can't be used any more.
 *
 * Returns 0 (`GIFSKI_OK`) on success, and non-0 `GIFSKI_*` constant on error.
 */
GifskiError gifski_finish(gifski *g);

#ifdef __cplusplus
}
#endif
