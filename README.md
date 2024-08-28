# emsdk-zig

```sh
zig build -l
# on windows => zig-out/bin/hello.exe
zig build -Dexamples
# on windows => zig-out/bin/hello.html
zig build -Dexamples -Dtarget=wasm32-freestanding
# on windows => zig-out/web/hello.html
zig build -Dexamples -Dtarget=wasm32-emscripten
```

## TODO: external use how to

## issues

- https://github.com/ziglang/zig/issues/10836
