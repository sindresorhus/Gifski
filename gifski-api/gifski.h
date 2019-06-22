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
gifski *g = gifski_new(&(GifskiSettings){});
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
*/

/**
 * Settings for creating a new encoder instance. See `gifski_new`
 */
typedef struct GifskiSettings {
  /**
   * Resize to max this width if non-0
   */
  uint32_t width;
  /**
   * Resize to max this height if width is non-0. Note that aspect ratio is not preserved.
   */
  uint32_t height;
  /**
   * 1-100, but useful range is 50-100. Recommended to set to 100.
   */
  uint8_t quality;
  /**
   * If true, looping is disabled. Recommended false (looping on).
   */
  bool once;
  /**
   * Lower quality, but faster encode.
   */
  bool fast;
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
  /** internal error related to multithreading */
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
  ABORTED,
  /** should not happen, file a bug */
  GIFSKI_OTHER,
};

typedef enum GifskiError GifskiError;

/**
 * Call to start the process
 *
 * See `gifski_add_frame_png_file` and `gifski_end_adding_frames`
 *
 * Returns a handle for the other functions, or `NULL` on error (if the settings are invalid).
 */
gifski *gifski_new(const GifskiSettings *settings);

/**
 * File path must be ASCII or valid UTF-8. This function is asynchronous.
 * Delay is in 1/100ths of a second.
 * Returns 0 (`GIFSKI_OK`) on success, and non-0 `GIFSKI_*` constant on error.
 */
GifskiError gifski_add_frame_png_file(gifski *handle,
                                      uint32_t index,
                                      const char *file_path,
                                      uint16_t delay);

/**
 * `pixels` is an array width×height×4 bytes large.
 * The array is copied, so you can free/reuse it immediately after this function returns.
 *
 * `index` is the frame number, counting from 0.
 * You can add frames in any order (if you need to), and they will be sorted by their index.
 *
 * Delay is in 1/100ths of a second. 5 is 20fps.
 *
 *
 * While you add frames, `gifski_set_file_output()` should have been called already.
 * If `gifski_set_file_output()` hasn't been called, it may make `gifski_add_frame_*` block and wait for
 * writing to start.
 * Returns 0 (`GIFSKI_OK`) on success, and non-0 `GIFSKI_*` constant on error.
 */
GifskiError gifski_add_frame_rgba(gifski *handle,
                                  uint32_t index,
                                  uint32_t width,
                                  uint32_t height,
                                  const unsigned char pixels[],
                                  uint16_t delay);

/** Same as `gifski_add_frame_rgba`, except it expects components in ARGB order.

Bytes per row must be multiple of 4, and greater or equal width×4.
If the bytes per row value is invalid (e.g. an odd number), frames may look sheared/skewed.
*/
GifskiError gifski_add_frame_argb(gifski *handle,
                                  uint32_t index,
                                  uint32_t width,
                                  uint32_t bytes_per_row,
                                  uint32_t height,
                                  const unsigned char pixels[],
                                  uint16_t delay);

/** Same as `gifski_add_frame_rgba`, except it expects RGB components (3 bytes per pixel)

Bytes per row must be multiple of 3, and greater or equal width×3.
If the bytes per row value is invalid (not multiple of 3), frames may look sheared/skewed.
*/
GifskiError gifski_add_frame_rgb(gifski *handle,
                                 uint32_t index,
                                 uint32_t width,
                                 uint32_t bytes_per_row,
                                 uint32_t height,
                                 const unsigned char pixels[],
                                 uint16_t delay);

/**
 * Get a callback for frame processed, and abort processing if desired.
 * The callback is called once per frame.
 *
 * It gets arbitrary pointer (`user_data`) as an argument. `user_data` can be `NULL`.
 * The callback must be thread-safe (it will be called from another thread).
 * The callback must return `1` to continue processing, or `0` to abort.
 *
 * Must be called before `gifski_set_file_output()` to take effect.
 */
void gifski_set_progress_callback(gifski *handle, int (*progress_callback)(void *user_data), void *user_data);

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
 * - size of the buffer to write, in bytes. IT MAY BE ZERO (when it's zero, either do nothing, or flush internal buffers if necessary).
 * - pointer to the buffer.
 * - context pointer to arbitary user data, same as passed in to this function.
 * The callback should return 0 (`GIFSKI_OK`) on success, and non-zero on error.
 * The callback function must be thread-safe.
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
 * After this call, the handle is freed and can't be used any more.
 *
 * Returns 0 (`GIFSKI_OK`) on success, and non-0 `GIFSKI_*` constant on error.
 */
GifskiError gifski_finish(gifski *g);

// Previous, deprecated name
#define gifski_drop(a) gifski_finish(a)

/**
 * Deprecated. Do not use.
 */
GifskiError gifski_write(gifski *, const char *);

/**
 * Optional. Allows deprecated `gifski_write` to finish.
 */
GifskiError gifski_end_adding_frames(gifski *handle);

#ifdef __cplusplus
}
#endif
