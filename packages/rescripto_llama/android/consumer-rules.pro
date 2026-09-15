# LlamaNative's external functions are bound by JNI name, and the text sink's
# onText method is looked up by name from native code. R8 must not rename
# either.
-keep class com.rescripto.llama.LlamaNative {
    native <methods>;
}
-keep interface com.rescripto.llama.LlamaNative$TextSink {
    *;
}
-keep class * implements com.rescripto.llama.LlamaNative$TextSink {
    public void onText(byte[]);
}
