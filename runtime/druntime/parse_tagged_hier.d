#!/usr/bin/env dub
/+
    dub.sdl:
    name "parse_tagged_hier"
+/

import std.algorithm;
import std.array;
import std.conv: to;
import std.file;
import std.exception: enforce;
import std.path;
import std.stdio;
import std.string: splitLines;
import std.typecons;

//TODO: add removing GEN_SRC file
//    echo "File '$DST_FILE' to '$DST_FILE.disabled' to avoid considering that tags parsing process was sucessfully done" >&2

int main(in string[] args)
{
    enforce(args.length >= 7 && args.length <= 8, "need 6 or 7 CLI arguments");

    immutable dstFile = args[1].buildNormalizedPath; /// i.e. GEN_SRCS file
    immutable srcCopyFile = args[2].buildNormalizedPath; /// i.e. mak/TAGGED_COPY //FIXME: rename var
    immutable dstCopyFile = args[3].buildNormalizedPath; /// i.e. GEN_COPY file, generated list of imports choised by tags
    immutable impDir = args[4].buildNormalizedPath; /// path to druntime ./import/ dir
    immutable tagsArg = args[5]; /// comma separated list of tags
    immutable srcDir = args[6]; /// path to druntime config/ dir //FIXME: rename var
    immutable externalConfigDir = (args.length > 7) ? args[7] : null; /// path to additional (external) config/ dir //FIXME: rename var

    enforce(srcCopyFile.isFile, `Tagged imports file '`~srcCopyFile~`' not found`);
    enforce(impDir.isDir, `DRuntime import/ dir '`~impDir~`' not found`);
    enforce(srcDir.isDir, `Tags dir '`~srcDir~`' not found`);

    if(externalConfigDir !is null)
        enforce(externalConfigDir.isDir, `Additional tags dir '`~externalConfigDir~`' not found`);

    if(dstFile.isValidFilename)
    {
        writeln(`Tagged sources list file '`~srcCopyFile~`' already generated`);
        return 0;
    }

    immutable string[] tags = tagsArg.split(",");

    writeln("Tags will be applied: ", tagsArg);

    //~ writeln("cfg dir: ", srcDir);

    immutable allConfigDirs = [srcDir, externalConfigDir];

    auto availTagsDirs = allConfigDirs
        .map!(a => a.dirEntries(SpanMode.shallow))
        .join
        .filter!(a => a.isDir)
        .map!(a => Tuple!(string, "base", string, "path")(a.name.baseName, a.name))
        .array
        .sort!((a, b) => a.base < b.base);

    static struct SrcElem
    {
        string basePath;    // ~/a/b/c/confing_dir/tag_1_name
        string tag;         // tag_1_name
        string relPath;    // core/internal/somemodule.d

        string fullPath() const => basePath~"/"~relPath;    // ~/a/b/c/confing_dir/tag_1_name/core/internal/somemodule.d
    }

    SrcElem[] resultSrcsList;

    foreach(tag; tags)
    {
        auto foundSUbdirs = availTagsDirs.filter!(a => a.base == tag);

        if(foundSUbdirs.empty)
        {
            stderr.writeln(`Warning: tag '`, tag, `' doesn't corresponds to any subdirectory inside of '`, allConfigDirs,`', skip`);
            continue;
        }

        // tag matched, files from matching dirs should be added to list recursively
        auto filesToAdd = foundSUbdirs.map!(
                d => dirEntries(d.path, SpanMode.depth)
                    .filter!(a => a.isFile)
                    .map!(e => SrcElem(d.path, tag, e.name[d.path.length+1 .. $]))
            ).join;

        //~ writeln(filesToAdd);

        foreach(f; filesToAdd)
        {
            auto found = resultSrcsList.find!((a, b) => a.relPath == b.relPath)(f);

            enforce(found.empty, `File '`~f.fullPath~`' overrides already defined file '`~found.front.fullPath~`'`);

            resultSrcsList ~= f;
        }
    }

    auto taggedImportsList = srcCopyFile.readText.replace(`\`, `/`).splitLines.sort.uniq.array;
    auto importsToCopy = File(dstCopyFile, "w");

    foreach(imp; taggedImportsList)
    {
        auto found = resultSrcsList.find!(a => a.relPath == imp);
        resultSrcsList.each!writeln;
        enforce(!found.empty, `Required for import file '`~imp~`' is not found in tagged sources`);

        importsToCopy.writeln(found.front.fullPath);
    }

    resultSrcsList.map!(a => a.fullPath).join("\n").toFile(dstFile);

    writeln("All tags applied");

    return 0;
}
