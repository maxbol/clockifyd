const std = @import("std");

fn addDeps(b: *std.Build, m: *std.Build.Module, dep_opts: anytype) void {
    m.addImport("zul", b.dependency("zul", dep_opts).module("zul"));
    m.addImport("clap", b.dependency("clap", dep_opts).module("clap"));
}
// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});
    const dep_opts = .{ .target = target, .optimize = optimize };

    const server_exe = b.addExecutable(.{
        .name = "clockifyd",
        .root_source_file = b.path("src/server.zig"),
        .target = target,
        .optimize = optimize,
    });
    addDeps(b, server_exe.root_module, dep_opts);

    const client_exe = b.addExecutable(.{
        .name = "clockifyd-get-current",
        .root_source_file = b.path("src/client.zig"),
        .target = target,
        .optimize = optimize,
    });
    addDeps(b, client_exe.root_module, dep_opts);

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(server_exe);

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(client_exe);

    // ~~~ ZLS stuff ~~~
    const check = b.step("check", "Check if the program compiles");
    const server_check_exe = b.addExecutable(.{
        .name = "clockifyd",
        .root_source_file = b.path("src/server.zig"),
        .target = target,
        .optimize = optimize,
    });
    addDeps(b, server_check_exe.root_module, dep_opts);
    const client_check_exe = b.addExecutable(.{
        .name = "clockifyd-get-current",
        .root_source_file = b.path("src/client.zig"),
        .target = target,
        .optimize = optimize,
    });
    addDeps(b, client_check_exe.root_module, dep_opts);
    check.dependOn(&server_check_exe.step);
    check.dependOn(&client_check_exe.step);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    // const run_server_cmd = b.addRunArtifact(server_exe);
    const run_client_cmd = b.addRunArtifact(client_exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    // run_server_cmd.step.dependOn(b.getInstallStep());
    run_client_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    // if (b.args) |args| {
    //     run_server_cmd.addArgs(args);
    // }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    // run_step.dependOn(&run_server_cmd.step);
    run_step.dependOn(&run_client_cmd.step);

    const server_exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    addDeps(b, server_exe_unit_tests.root_module, dep_opts);

    const run_server_exe_unit_tests = b.addRunArtifact(server_exe_unit_tests);

    const client_exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    addDeps(b, client_exe_unit_tests.root_module, dep_opts);

    const run_client_exe_unit_tests = b.addRunArtifact(client_exe_unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_server_exe_unit_tests.step);
    test_step.dependOn(&run_client_exe_unit_tests.step);
}
