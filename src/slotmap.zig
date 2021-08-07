const std = @import("std");

pub fn Key(comptime S: type) type {
    return struct {
        const Self = @This();

        index: S,
        version: S,

        pub fn equals(lhs: Self, rhs: Self) bool {
            return lhs.index == rhs.index and lhs.version == rhs.version;
        }
    };
}
fn Slot(comptime S: type, comptime T: type) type {
    return struct {
        const Self = @This();

        version: S,
        next_free: S,
        value: T,

        fn new(version: S, next_free: S, value: T) Self {
            return Self{ .version = version, .next_free = next_free, .value = value };
        }

        fn occupied(self: Self) bool {
            return self.version % 2 > 0;
        }
    };
}

pub fn SlotMap(comptime S: type, comptime T: type) type {
    return struct {
        const Self = @This();
        const SlotType = Slot(S, T);

        pub const Error = error{
            OverflowError,
            InvalidKey,
        };

        pub const Iterator = struct {
            map: *const Self,
            index: S,

            pub fn keys(self: *Iterator) ?Key(S) {
                if (self.map.len == 0 or self.index > self.map.len) {
                    self.reset();
                    return null;
                }
                while (!self.map.slots.items[self.index].occupied()) : (self.index += 1) {}
                self.index += 1;

                return Key(S){
                    .index = self.index - 1,
                    .version = self.map.slots.items[self.index - 1].version,
                };
            }

            pub fn values(self: *Iterator) ?T {
                if (self.map.len == 0 or self.index > self.map.len) {
                    self.reset();
                    return null;
                }
                while (!self.map.slots.items[self.index].occupied()) : (self.index += 1) {}
                self.index += 1;
                return self.map.slots.items[self.index - 1].value;
            }

            fn reset(self: *Iterator) void {
                self.index = 0;
            }
        };

        slots: std.ArrayList(SlotType),
        free_head: S,
        len: S,

        pub fn init(allocator: *std.mem.Allocator, size: S) !Self {
            var result = Self{
                .slots = try std.ArrayList(SlotType).initCapacity(allocator, @intCast(usize, size)),
                .free_head = 0,
                .len = 0,
            };

            return result;
        }

        pub fn deinit(self: Self) void {
            self.slots.deinit();
        }

        pub fn count(self: Self) usize {
            return @intCast(usize, self.len);
        }

        pub fn capacity(self: Self) usize {
            return self.slots.capacity;
        }

        pub fn ensureCapacity(self: *Self, new_capacity: usize) !void {
            try self.slots.ensureTotalCapacity(new_capacity);
        }

        pub fn hasKey(self: Self, key: Key(S)) bool {
            if (key.index < self.slots.items.len) {
                const slot = self.slots.items[key.index];
                return slot.version == key.version;
            } else {
                return false;
            }
        }

        pub fn insert(self: *Self, value: T) !Key(S) {
            const new_len = self.len + 1;

            if (new_len == std.math.maxInt(S)) {
                return error.OverflowError;
            }

            const idx = self.free_head;

            if (idx < self.slots.items.len) {
                const occupied_version = self.slots.items[idx].version | 1;
                const result = Key(S){ .index = idx, .version = occupied_version };

                self.slots.items[idx].value = value;
                self.slots.items[idx].version = occupied_version;
                self.free_head = self.slots.items[idx].next_free;
                self.len = new_len;

                return result;
            } else {
                const result = Key(S){ .index = idx, .version = 1 };

                try self.slots.append(SlotType.new(1, 0, value));
                self.free_head = @intCast(S, self.slots.items.len);
                self.len = new_len;

                return result;
            }
        }

        // TODO: find out how to do this correctly
        fn reserve(self: *Self) !Key(S) {
            const default: T = undefined;
            return try self.insert(default);
        }

        fn removeFromSlot(self: *Self, idx: S) T {
            self.slots.items[idx].next_free = self.free_head;
            self.slots.items[idx].version += 1;
            self.free_head = idx;
            self.len -= 1;
            return self.slots.items[idx].value;
        }

        pub fn remove(self: *Self, key: Key(S)) !T {
            if (self.hasKey(key)) {
                return self.removeFromSlot(key.index);
            } else {
                return error.InvalidKey;
            }
        }

        pub fn delete(self: *Self, key: Key(S)) !void {
            if (self.hasKey(key)) {
                _ = self.removeFromSlot(key.index);
            } else {
                return error.InvalidKey;
            }
        }

        // TODO: zig closures
        fn retain(self: *Self, filter: fn (key: Key(S), value: T) bool) void {
            const len = self.slots.len;
            var idx = 0;

            while (idx < len) : (idx += 1) {
                const slot = self.slots[idx];
                const key = Key{ .index = idx, .version = slot.version };
                if (slot.occupied and !filter(key, value)) {
                    _ = self.removeFromSlot(idx);
                }
            }
        }

        pub fn clear(self: *Self) void {
            while (self.len > 0) {
                _ = self.removeFromSlot(self.len);
            }

            self.slots.shrinkRetainingCapacity(0);
            self.free_head = 0;
        }

        pub fn get(self: *const Self, key: Key(S)) !T {
            if (self.hasKey(key)) {
                return self.slots.items[key.index].value;
            } else {
                return error.InvalidKey;
            }
        }

        pub fn getPtr(self: *const Self, key: Key(S)) !*T {
            if (self.hasKey(key)) {
                return &self.slots.items[key.index].value;
            } else {
                return error.InvalidKey;
            }
        }

        pub fn set(self: *Self, key: Key(S), value: T) !void {
            if (self.hasKey(key)) {
                self.slots.items[key.index].value = value;
            } else {
                return error.InvalidKey;
            }
        }

        pub fn iterator(self: *const Self) Iterator {
            return Iterator{
                .map = self,
                .index = 0,
            };
        }
    };
}

test "slotmap" {
    // const debug = std.debug;
    const mem = std.mem;
    const expect = std.testing.expect;
    const expectError = std.testing.expectError;

    const data = [_][]const u8{ "foo", "bar", "cat", "zag" };

    var map = try SlotMap(u16, []const u8).init(std.testing.allocator, 3);
    const K = Key(u16);
    var keys = [_]K{K{ .index = 0, .version = 0 }} ** 3;
    var iter = map.iterator();
    var idx: usize = 0;

    defer map.deinit();

    for (data[0..3]) |word, i| {
        keys[i] = try map.insert(word);
    }

    try expect(mem.eql(u8, try map.get(keys[0]), data[0]));
    try expect(mem.eql(u8, try map.get(keys[1]), data[1]));
    try expect(mem.eql(u8, try map.get(keys[2]), data[2]));

    try map.set(keys[0], data[3]);
    try expect(mem.eql(u8, try map.get(keys[0]), data[3]));
    try map.delete(keys[0]);

    try expectError(error.InvalidKey, map.get(keys[0]));

    while (iter.values()) |value| : (idx += 1) {
        try expect(mem.eql(u8, value, data[idx + 1]));
    }

    idx = 0;

    while (iter.keys()) |key| : (idx += 1) {
        try expect(mem.eql(u8, try map.get(key), data[idx + 1]));
    }

    map.clear();

    // std.debug.warn("\n");

    for (keys) |key| {
        try expectError(error.InvalidKey, map.get(key));
    }

    while (iter.values()) |_| {
        try expect(iter.index == 0);
    }
}
