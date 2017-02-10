#!/usr/bin/rdmd
// "Bad interpreter"?  Download dmd from <https://dlang.org>.

// This program downloads as many as possible of the files listed at
// <https://github.com/climate-mirror/datasets/issues/272>.  Instructions for
// Linux:
//
// 1. Copy the long list of URLs from that Github issue into a file called
//    links.txt
//
// 2. Visit <https://dlang.org>; download and install DMD, the reference D
//    compiler.
//
// 3. Make sure lftp is installed on your computer.  On Linux, `which lftp' will
//    show something if lftp is installed and not otherwise.
//
// 4. Download getcoris.d into a new directory.
//
// 5. Make it executable:
//
//      chmod +x getcoris.d
//
// 6. Run it:
//      ./getcoris.d
//
//    It'll take a few seconds to compile, and then it'll start producing
//    screen output to show its progress.  It'll create directory trees
//    automatically.  To see what you've downloaded, type `find'.
//
// 7. getcoris.d downloads files in a random order, partly to spread the load
//    across servers (to make best use of your banwidth and reduce the chances
//    of your being banned), and partly so that several people running
//    getcoris.d will achieve greater coverage, even if none of them manages a
//    complete download.
//
// 8. If you interrupt getcoris.d with Ctrl+C and later restart it, it'll
//    first download the files it was in the middle of downloading before (to
//    minimise the number of truncated files on your file system) and then
//    download only those files it doesn't already have.  Nevertheless, not
//    every server supports resumable downloads, so try to interrupt
//    getcoris.d as infrequently as possible.
//
// This is not an industrial-strength downloader, and doesn't cope robustly with
// (for example) I/O errors in the progress file.  It's a throw-away program to
// download one large data set, starting as soon as possible.  Sometimes, good
// enough is good enough.
//
// This program has been tested on Linux only.  I haven't tested it on Windows,
// because my employer asks me not to use its resources for OSS development,
// but I'll happily take bug reports or (even better) pull requests from Windows
// users.
//
// To do:
//   * Do we need to get screen output under control?  Show what's completed
//     as well as what's started?


import std.algorithm.comparison;
import std.algorithm.iteration;
import std.array;
import std.file;
import std.format;
import std.parallelism;
import std.process;
import std.random;
import std.range;
import std.regex;
import std.stdio;

// How many parallel downloads would you like?
enum NrParallelJobs     = 4;

// What's the name of your text file full of links?
enum LinkFileName       = "links.txt";

// What's the name of the progress file that enables us to resume downloading
// if we're interrupted?
enum ProgressFileName   = "progress.txt";

// False to download files, true just to say what we'd do:
enum DryRun             = false;

// Status of a single download or mirror operation:
enum Progress {None, Started, Finished}

// Update the progress file:

auto update(in Progress progress, in char[] url) {
    assert(progress != Progress.None);
    const prefix = progress == Progress.Started? "S ": "F ";

    synchronized {
        auto fh = File(ProgressFileName, "a");
        fh.writeln(prefix, url);
    }
}

// Run a single command, or just dump it to the screen if in dry-run mode:

auto execute(const char[][] argv, const char[] url) {
    update(Progress.Started, url);
    if (DryRun) {
        import core.thread;
        writeln(argv);
        Thread.sleep(dur!"seconds"(2));
        update(Progress.Finished, url);
    }
    else {
        auto pid = spawnProcess(argv);
        const rc = wait(pid);
        if (rc != 0)
            writeln("Warning: exit code ", rc, " from ", argv.join(' '));
        else
            update(Progress.Finished, url);
    }
}

// Use lftp to mirror an entire directory tree:

auto mirror_directory(in char[] url, in char[] directory) {
    mkdirRecurse(directory);
    const commands = format("open %s; mirror --continue --parallel=2 . %s", url, directory);
    const args     = ["lftp", "-c", commands];
    execute(args, url);
}

// Use lftp to download a single file:

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
    const commands = format("open %s; get -c -O %s %s", remote_directory, local_directory, base_name);
    const args     = ["lftp", "-c", commands];
    execute(args, url);
}

// Handle a single URL of any type:

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

// Upon startup, read the progress file maintained by update() above:

alias ProgressFile = Progress[string];

enum rx_progress_line = ctRegex!(`^ ([SF]) \s (\S+)`, "x");

auto read_progress_file(ref ProgressFile pfile) {
    // The first time getcoris is run, the progress file won't exist:
    if (!exists(ProgressFileName))
        return;

    // If it does exist, though, it'd better be readable, because we don't
    // want to waste bandwidth by silently failing to read it.
    foreach (line; File(ProgressFileName).byLineCopy)
        if (auto caps = line.matchFirst(rx_progress_line)) {
            auto indicator = caps[1], url = caps[2];
            auto progress = indicator[0] == 'S'? Progress.Started: Progress.Finished;

            if (auto ptr = url in pfile)
                *ptr = max(*ptr, progress);
            else
                pfile[url] = progress;
        }
}

static assert(NrParallelJobs > 1);

// Read the progress file and the list of URLs; download all files we've not
// yet downloaded, starting with any work in progress:

void main() {
    ProgressFile prog_file;
    read_progress_file(prog_file);

    auto started_urls   = prog_file.byKey
        .filter!(url => (prog_file[url] == Progress.Started));

    auto unstarted_urls = File(LinkFileName)
        .byLineCopy
        .filter!(url => url !in prog_file)
        .array
        .randomCover;

    auto pending_urls = chain(started_urls, unstarted_urls);

    defaultPoolThreads  = NrParallelJobs - 1;
    foreach (link; parallel(pending_urls, 1))
        do_one_url(link);
}

