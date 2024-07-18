#!/usr/bin/env dub
/+
    dub.sdl:
    name "parse_tagged_hier"
+/

import std.file;
import std.exception: enforce;
import std.path;
import std.stdio;

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

    import std.stdio;
    writeln(args);

//~ TAGS_LIST=($(echo "$TAGS" | tr "," "\n"))

//~ echo -e "\nTags will be applied: $TAGS"

//~ APPLIED=""

//~ WARN_ACCUM=""

//~ function applyTaggedFiles {
    //~ TAG=$1
    //~ SRC_TAG_DIR=$2/${TAG}

    //~ if [[ ! -d ${SRC_TAG_DIR} ]]; then
        //~ WARN_ACCUM+="Warning: tag '${TAG}' doesn't corresponds to any subdirectory inside of '$2', skip\n"
    //~ else
        //~ SRC_FILES_LIST+=($(find ${SRC_TAG_DIR} -type f ))

        //~ pushd ${SRC_TAG_DIR} > /dev/null
        //~ MAYBE_COPY_LIST+=($(find * -type f ))
        //~ popd > /dev/null
    //~ fi
//~ }

//~ for tag in "${TAGS_LIST[@]}"
//~ do
    //~ WARN_ACCUM="Warnings:\n"

    //~ applyTaggedFiles ${tag} ${SRC_DIR}

    //~ if [ -v SRC_DIR_ADDITIONAL ]; then
        //~ applyTaggedFiles ${tag} ${SRC_DIR_ADDITIONAL}

        //~ if [[ $(echo ${WARN_ACCUM} | grep -c '^') -gt 2 ]]; then
            //~ echo -ne "${WARN_ACCUM}" >&2
        //~ fi
    //~ else
        //~ if [[ $(echo ${WARN_ACCUM} | grep -c '^') -gt 1 ]]; then
            //~ echo -ne "${WARN_ACCUM}" >&2
        //~ fi
    //~ fi

    //~ APPLIED+=" $tag"

    //~ #echo "Currently applied tags:$APPLIED"
//~ done

//~ LINES_TO_COPY=$(grep -v '^$' ${SRC_COPY_FILE} | sort | uniq | wc -l)
//~ COPIED=0

//~ mkdir -p $(dirname ${DST_FILE})
//~ mkdir -p $(dirname ${DST_COPY_FILE})
//~ echo -ne > ${DST_FILE}
//~ echo -ne > ${DST_COPY_FILE}

//~ for i in "${!SRC_FILES_LIST[@]}"
//~ do
    //~ echo ${SRC_FILES_LIST[$i]} >> ${DST_FILE}

    //~ maybe_copy=$(echo ${MAYBE_COPY_LIST[$i]} | tr '/' '\\')

    //~ # Adds copy entry if file mentioned in the list
    //~ grep -F "$maybe_copy" ${SRC_COPY_FILE} > /dev/null && {
        //~ echo ${IMPDIR}'/'${SRC_FILES_LIST[$i]} >> ${DST_COPY_FILE}
        //~ COPIED=$((COPIED+1))
    //~ }
//~ done

//~ if [ $COPIED -ne $LINES_TO_COPY ]; then
    //~ echo "File '$SRC_COPY_FILE' contains $LINES_TO_COPY meaningful line(s), but to '$DST_COPY_FILE' added $COPIED line(s)" >&2

    //~ mv ${DST_FILE} "$DST_FILE.disabled"
    //~ echo "File '$DST_FILE' to '$DST_FILE.disabled' to avoid considering that tags parsing process was sucessfully done" >&2
    //~ exit 1
//~ fi

//~ echo "All tags applied"

    return 0;
}
