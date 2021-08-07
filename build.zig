const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();

    const lib = b.addStaticLibrary("slotmap", "src/slotmap.zig");
    lib.setBuildMode(mode);
    lib.install();

    var main_tests = b.addTest("src/slotmap.zig");
    main_tests.setBuildMode(mode);

    const test_step = b.step("test", "run library tests");
    test_step.dependOn(&main_tests.step);

    b.default_step.dependOn(&lib.step);
}
