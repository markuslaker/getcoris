#!/usr/bin/rdmd
// "Bad interpreter"?  Download dmd from <https://dlang.org>.

// This program shows the progress made so far by getcoris.d.
//
// Files that couldn't be downloaded when getcoris.d tried are marked as still
// being in progress, in case the failure is temporary; this enables a second
// execution of getcoris.d to recover from any temporary failures.  Keep
// running getcoris.d until it stops doing anything useful, and then assume
// that any remaining failures are permanent.

import std.container.rbtree;
import std.regex;
import std.stdio;

// What's the name of the progress file that enables us to resume downloading
// if we're interrupted?
enum ProgressFileName   = "progress.txt";

alias UrlSet = RedBlackTree!string;

enum rx_line = ctRegex!(`^ ([SF]) \s (\S+)`, "x");

auto read_progress(UrlSet started_urls, UrlSet finished_urls) {
    foreach (line; File(ProgressFileName).byLineCopy)
        if (auto caps = line.matchFirst(rx_line)) {
            const state = caps[1];
            const url   = caps[2];
            if (state[0] == 'F') {      // finished
                started_urls .removeKey(url);
                finished_urls.insert(url);
            }
            else if (url !in finished_urls)
                started_urls.insert(url);
        }
}

auto show(const UrlSet urls, in string narrative) {
    writeln(narrative);
    writeln;
    foreach (url; urls)
        writeln(url);
}

void main() {
    auto started_urls = new UrlSet, finished_urls = new UrlSet;
    read_progress(started_urls, finished_urls);
    show(finished_urls, "Downloaded data:");
    writeln;
    writeln;
    show(started_urls, "Data still being downloaded, or not yet downloaded successfully:");
}

