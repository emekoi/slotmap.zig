const std = @import("std");

pub const Key = struct {
    const Self = @This();

    index: u32,
    version: u32,

    pub fn equals(lhs: Self, rhs: Self) bool {
        return lhs.index == rhs.index and lhs.version == rhs.version;
    }
};

fn Slot(comptime T: type) type {
    return struct {
        const Self = @This();

        version: u32,
        next_free: u32,
        value: T,

        fn new(version: u32, next_free: u32, value: T) Self {
            return Self {
                .version = version,
                .next_free = next_free,
                .value = value
            };
        }

        fn occupied(self: Self) bool {
            return self.version % 2 > 0;
        }
    };
}

pub fn SlotMap(comptime T: type) type {
    return struct {
        const Self = @This();
        const SlotType = Slot(T);

        slots: std.ArrayList(SlotType),
        free_head: usize,
        len: usize,

        pub fn init(size: usize) !Self {
            const result = Self {
                .slots = std.ArrayList(SlotType).init(),
                .free_head = 0,
                .len = 0,
            };
            try result.slots.resize();
            return result;
        }

        pub fn deinit(self: Self) void {
            self.slots.deinit();
        }

        pub inline fn count(self: Self) usize {
            return self.len;
        }

        pub inline fn capacity(self: Self) usize {
            return self.slots.capacity();
        }

        pub fn has_key(self: Self, key: Key) bool {
            if (key.index < self.slots.count()) {
                const slot = self.slots.get(key.index);
                return slot.version == key.version;
            } else {
                return false;
            }
        }

        pub fn insert(self: *Self, value: T) !Key {
            const new_len = self.len + 1;

            if (new_len == @maxValue(u32)) {
                return error.OverflowError;
            }
            
            const idx = self.free_head;

            if (idx < self.slots.count()) {
                const slot = &self.slots.at(idx);
                const occupied_version = slot.*.version | 1;
                const result = Key {
                    .index = idx,
                    .version = occupied_version
                };
                
                slot.*.value = value;
                slot.*.version = occupied_version;
                self.free_head = slot.*.next_free;
                self.len = new_len;

                return result;
            } else {
                const result = Key { .index = idx, .version = 1 };
                
                self.slots.append(SlotType.new(1, 0, value));
                self.free_head = self.slots.count();
                self.len = new_len;

                return result;
            }
        }
    };
}

test "slotmap" {
    var map = SlotMap([]const u8).new(3);
    const k1 = map.insert("foo");
    const k2 = map.insert("bar");
    const k3 = map.insert("foobar");

    std.debug.warn("{}\n", map.get(k1));
    std.debug.warn("{}\n", map.get(k2));
    std.debug.warn("{}\n", map.get(k4));
}
