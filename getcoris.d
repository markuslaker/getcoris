#!/usr/bin/rdmd
// "Bad interpreter"?  Download dmd from <https://dlang.org>.

// This program downloads as many as possible of the files listed at
// <https://github.com/climate-mirror/datasets/issues/272>.  You'll need to
// copy those links into a file and supply it to getcoris.d
// You'll also need lftp.
//
// To do:
//   * Add persistent state to make interrupted downloads resumable without
//     requiring the user to edit text files (ugh).
//   * After that, shuffle the input, so that
//      * We don't all hit the same servers at once;
//      * If none of us manages to download everything, we increase coverage
//        by not all having the same subset; and
//      * Each client uses bandwidth more efficiently by downloading from
//        more servers at once; the incoming list of links is grouped by
//        server.
//   * Do we need to get screen output under control?  Show what's completed
//     as well as what's started?
//
// This program has been tested on Linux only.  I haven't tested it on Windows,
// because my employer asks me not to use its resources for OSS development,
// but I'll happily take bug reports or (even better) pull requests from Windows
// users once the to-do list is done (but not until then, please).

import std.file;
import std.format;
import std.parallelism;
import std.process;
import std.regex;
import std.stdio;

// How many parallel downloads would you like?
enum NrParallelJobs = 4;

// What's the name of your text file full of links?
enum LinkFileName   = "links.txt";

auto mirror_directory(in char[] url, in char[] directory) {
    mkdirRecurse(directory);
    const commands = format("open %s; mirror -P=2 . %s", url, directory);
    const args     = ["lftp", "-c", commands];
    writeln(args);
    auto pid = spawnProcess(args);
    const rc = wait(pid);
    if (rc != 0)
        writeln("Warning: exit code ", rc, " from lftp -c ", commands);
}

enum rx_path_and_base = ctRegex!(`(.+) / (.+)`, "x");

auto download_file(in char[] url, in char[] resource) {
    const(char)[] local_directory, remote_directory, base_name;
    if (auto caps = resource.matchFirst(rx_path_and_base)) {
        local_directory = caps[1];
        base_name       = caps[2];
    }
    else
        return;

    if (auto caps = url.matchFirst(rx_path_and_base))
        remote_directory = caps[1];
    else
        return;

    // Now, for ftp://ftp.example.com/data/subdir/foo.txt,
    //  * local_directory  = "ftp.example.com/data/subdir"
    //  * remote_directory = "ftp://ftp.example.com/data/subdir"
    //  * base_name        = "foo.txt"

    mkdirRecurse(local_directory);
    const commands = format("open %s; get -O %s %s", remote_directory, local_directory, base_name);
    const args     = ["lftp", "-c", commands];
    writeln(args);
    auto pid = spawnProcess(args);
    const rc = wait(pid);
    if (rc != 0)
        writeln("Warning: exit code ", rc, " from lftp -c ", commands);
}

enum rx_no_protocol  = ctRegex!(` ^ ([a-z]+ ://) (.{4,})`,                  "x");
enum rx_is_directory = ctRegex!(` / $ `,                                    "x");
enum rx_usable_file  = ctRegex!(` \. (?! asp x? | htm l? | php) [a-z]+ $ `, "x");

auto do_one_url(const(char)[] url) {
    const(char)[] protocol, resource;
    if (auto caps = url.matchFirst(rx_no_protocol)) {
        protocol = caps[1];
        resource = caps[2];
    }
    else
        return;

    if (url.matchFirst(rx_is_directory))
        mirror_directory(url, resource[0 .. $-2]);
    else if (url.matchFirst(rx_usable_file))
        download_file(url, resource);
}

static assert(NrParallelJobs > 1);

void main() {
    auto resources     = File(LinkFileName).byLineCopy;
    defaultPoolThreads = NrParallelJobs - 1;
    foreach (link; parallel(resources, 1))
        do_one_url(link);
}

