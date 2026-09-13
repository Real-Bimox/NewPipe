# NewPipe segfaults during playback: use-after-free of native ICU RegexPattern (sun.misc.Cleaner processed while referent is reachable)

## Summary

The NewPipe Flatpak (net.newpipe.NewPipe, BaseApp build of ~2026-06-19) crashes
with SIGSEGV whenever video playback starts. The same crash reproduces on the
current BaseApp stable (ATL 923b6df1, GNOME 50 runtime) on a machine with
proprietary NVIDIA graphics.

## Evidence

Three coredumps (`coredumpctl`), two during playback, one during feed load at
startup. Identical backtrace in all three:

```
#11 icu_77::RegexMatcher::RegexMatcher(icu_77::RegexPattern const*)   libicui18n.so.77.1
#12 icu_77::RegexPattern::matcher(UErrorCode&) const                  libicui18n.so.77.1
#13 <libjavacore.so> java_util_regex_Matcher openImpl
#14 <compiled Java code>
```

Faulting instruction and registers (gdb, `frame 11`):

```
=> mov 0xef8(%rax),%rsi    ; rax = 0
```

Memory at the `RegexPattern*` argument contains the ASCII string
`"Fatal signal 11 SIGSEGV, code 1 (SEGV_MAPERR)"` — i.e. the native pattern
object was freed and its heap chunk recycled (into ART's own crash-message
buffer). The Java `Pattern` object still holds the dangling address, so the
object was collected/freed while still in use.

Crashing thread: `ExoPlayer:Loade` (NewPipeExtractor regex parsing on ExoPlayer's
loader thread). Host: Fedora 44 (Bazzite), kernel 7.2.3, NVIDIA 595.71.05.

libjavacore.so links libicui18n.so.77 / libicuuc.so.77 and references only
`icu_77`-mangled symbols, matching the runtime — this is not an ICU ABI
mismatch; it is a premature free.

## Root-cause hypothesis

`libcore.util.NativeAllocationRegistry` frees native allocations through
`sun.misc.Cleaner`. The art_standalone runtime ("frankenstained" ART on the
dalvik branch) appears to run cleaners while their referents are still strongly
reachable, deleting live native objects (observed with `java.util.regex.Pattern`
→ `icu::RegexPattern`).

## Workaround patch (art_standalone)

Keep cleaner-managed native allocations alive for the process lifetime in
`NativeAllocationRegistry.registerNativeAllocation(Object, long)`; the returned
explicit-free Runnable still frees exactly once. Bounded native-memory growth
for a session vs. hard crashes.

## Related: broken VA-API path on NVIDIA hosts

On hosts where the VA driver cannot allocate surfaces (proprietary NVIDIA),
every hardware decode attempt fails (`AVHWFramesContext: Failed to create
surface`, `hardware accelerator failed to decode picture`) and no video frame
is ever produced. Patch adds `ATL_DISABLE_HW_DECODE` to skip VA-API/DRM_PRIME
selection in `MediaCodec.native_configure_video`, falling back to software
decoding (swscale render path).

Both patches are applied in the local build at
`local-repos/newpipe-flatpak-fix/` on this host.
