# emsdk-zig

`zig-0.15.1`

```sh
zig build -l
# on windows => zig-out/bin/hello.exe
zig build -Dexamples
# on windows => zig-out/web/hello.html
zig build -Dexamples -Dtarget=wasm32-emscripten
```

`zig-0.15.1 not work`

```
# on windows => zig-out/bin/hello.html
zig build -Dexamples -Dtarget=wasm32-freestanding

error: error: unable to provide libc for target 'wasm32-freestanding-none'
```

## issues

`zig-0.14`

- https://github.com/ziglang/zig/issues/10836
