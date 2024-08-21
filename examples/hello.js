// const importObject = {
//   env: {
//     __memory_base: 0,
//     __table_base: 0,
//     memory: new WebAssembly.Memory({ initial: 1024 }),
//     table: new WebAssembly.Table({ initial: 0, element: 'anyfunc' }),
//     emscripten_resize_heap: arg => 0,
//     __handle_stack_overflow: () => console.log("overflow"),
//   },
//   imports: { imported_func: arg => console.log(arg) }
// };

const getMemory = () => new DataView(instance.exports.memory.buffer);

const memGet = (ptr, len) => new Uint8Array(getMemory().buffer, ptr, len);

const memToString = (ptr, len) => {
  let array = null;
  if (len) {
    array = memGet(ptr, len);
  }
  else {
    // zero terminated
    let i = 0;
    const buffer = new Uint8Array(getMemory().buffer, ptr);
    for (; i < buffer.length; ++i) {
      if (buffer[i] == 0) {
        break;
      }
    }
    array = new Uint8Array(getMemory().buffer, ptr, i);
  }
  const decoder = new TextDecoder()
  const text = decoder.decode(array)
  return text;
}

let importObject = {
  env: {
    console_logger: (level, ptr, len) => {
      const message = memToString(ptr, len);
      switch (level) {
        case 0:
          console.error(message);
          break;

        case 1:
          console.warn(message);
          break;

        case 2:
          console.info(message);
          break;

        default:
          console.debug(message);
          break;
      }
    },
  }
};
const response = await fetch("hello.wasm");
const buf = await response.arrayBuffer();
const { instance } = await WebAssembly.instantiate(buf, importObject);

console.log(instance);
instance.exports.main();
