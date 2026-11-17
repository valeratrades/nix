# Logic duplication left after moving terminal charts onto `v_utils::chart`

- `~/s/ev/_sa/verif_vid/verif_vid_edit/src/timings.rs` (`write`, the `step` array and the self-time `covered` sweep) vs
  `v_utils::chart::gantt`'s tick step and `home/scripts/build_gantt.rs::union`.
  The SVG/HTML gantt there picks its own tick step and computes interval unions by hand. Sharing them means v_utils
  exporting a tick-step and an interval-union primitive; neither has a second consumer outside these two, and the SVG
  renderer is the only non-terminal chart, so it waits until another one appears.
