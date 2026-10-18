# Test assets

| File              | Source                                                                                                              | License   |
| ----------------- | ------------------------------------------------------------------------------------------------------------------- | --------- |
| `sample.heic`     | [strukturag/libheif](https://github.com/strukturag/libheif) — `fuzzing/data/corpus/colors-no-alpha.heic` (HEVC, no alpha) | LGPL-3.0  |
| `thumbnail.heic`  | Written for this project with `heif-enc -t 16 -o thumbnail.heic blue.png` (64x48 image with a 16x12 thumbnail)       | GPL-3.0   |
| `two-images.heic` | Written for this project with `heif-enc -o two-images.heic blue.png pink.png` (two top-level 64x48 images)          | GPL-3.0   |

`sample.heic` is a tiny valid HEIC image used to exercise the conversion code paths in the unit tests.

`thumbnail.heic` and `two-images.heic` check the frame count: a thumbnail is not a second image, two top-level images are. They were written with libheif 1.17.6 (`heif-enc`, x265 encoder) on Ubuntu 24.04 (`apt install libheif-examples libheif-plugin-x265`). The inputs are solid 64x48 PNG files: `blue.png` filled with `#4080C0` and `pink.png` with `#C04080` (`convert -size 64x48 xc:#4080C0 blue.png`).
