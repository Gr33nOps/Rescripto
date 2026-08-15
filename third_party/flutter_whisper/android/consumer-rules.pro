# WhisperContext is entered from native code through exported JNI methods,
# and onNativeProgress is looked up by its exact name and signature.
-keep class io.github.govindtank.flutter_whisper.WhisperContext {
    *;
}
