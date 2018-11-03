# *slotmap.zig*

a slotmap for zig

## usage
```
const std = @import("std");
const slotmap = @import("slotmap");

const debug = std.debug;
const mem = std.mem;
const assert = debug.assert;

pub fn main() !void {
  var map = try SlotMap([]const u8).init(std.debug.global_allocator, 0);
  defer map.deinit();

  const key = try map.insert("hello world");
  assert(mem.eql(u8, try map.get(key), "hello world"));
  
  try map.set(key, "goodbye");
  assert(mem.eql(u8, try map.get(key), "goodbye"));
}
```
