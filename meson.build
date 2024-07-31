project(
    'Runtime library for the D language with custom targets support',
    ['d', 'c', 'cpp'],
)

# Cmake module is broken for ldc2:
# https://github.com/mesonbuild/meson/issues/13390
#
# So using custom_target and bash wrapper

ldc2 = find_program('ldc2')

cmake = find_program('cmake_wrapper.sh')

target_system = meson.get_external_property('target_system', 'AUTO')
external_tags = meson.get_external_property('external_tags', '')
tags_opts = (external_tags == '') ? [] : [
    '-D', 'CMAKE_SYSTEM_NAME=EXTERNAL',
    '-D', 'TARGET_SYSTEM=' + target_system,
    '-D', 'EXTERNAL_TAGS=' + external_tags,
]

dflopt = get_option('default_library')

if get_option('debug') == true
    debug_suffix = '-debug'
else
    debug_suffix = ''
endif

# Build debug and release versions just because we can
#TODO: It's disgusting:
if dflopt == 'shared'
    build_shared = 'ON'
    druntime_ninja_taget = 'libdruntime-ldc'+debug_suffix+'-shared.so'
    phobos_ninja_target = 'libphobos2-ldc'+debug_suffix+'-shared.so'
    druntime_tgts = [druntime_ninja_taget]
    phobos_tgts = [phobos_ninja_target]
elif dflopt == 'static'
    build_shared = 'OFF'
    druntime_ninja_taget = 'libdruntime-ldc'+debug_suffix+'.a'
    phobos_ninja_target = 'libphobos2-ldc'+debug_suffix+'.a'
    druntime_tgts = [druntime_ninja_taget]
    phobos_tgts = [phobos_ninja_target]
else
    build_shared = 'BOTH'
    druntime_ninja_taget = 'libdruntime-ldc'+debug_suffix+'-shared.so'
    phobos_ninja_target = 'libphobos2-ldc'+debug_suffix+'-shared.so'
    druntime_tgts = [druntime_ninja_taget, 'libdruntime-ldc'+debug_suffix+'.a']
    phobos_tgts = [phobos_ninja_target, 'libphobos2-ldc'+debug_suffix+'.a']
endif

base_opts = [
        '-G', 'Ninja',
        '-D', 'LDC_EXE_FULL=' + ldc2.full_path(),
        '-D', 'DMDFE_MINOR_VERSION=109',
        '-D', 'DMDFE_PATCH_VERSION=1',
        '-D', 'CMAKE_C_COMPILER=' + meson.get_compiler('c').get_id(),
        '-D', 'RT_CFLAGS=' + ' '.join(meson.get_external_property('c_args_external', '')),
        '-D', 'CMAKE_SYSTEM_PROCESSOR=' + host_machine.cpu_family(),
        '-D', 'BUILD_SHARED_LIBS=' + build_shared,
        '-D', 'C_SYSTEM_LIBS=',
] + tags_opts

d_args_semi = ';'.join(
    meson.get_external_property('d_args_external', '')
)

druntime_tgt = custom_target('druntime_tgt',
    output: druntime_tgts,
    command :
    [
        cmake,
        druntime_ninja_taget, #ninja target, FIXME: must be able to build both targets simultaneously
        '@OUTDIR@', #copy target to this dir
        '-S', '@CURRENT_SOURCE_DIR@' / 'runtime',
        '-B', '@PRIVATE_DIR@',
        '-D', 'D_EXTRA_FLAGS='+d_args_semi+';-conf=',
    ] + base_opts,
    install: true,
    install_dir: 'lib',
)

tagged_include_dir = meson.current_build_dir() / druntime_ninja_taget+'.p/import/tagged_imports' / meson.get_external_property('target_system', host_machine.system())

common_cfg_dict = {
    'ADDITIONAL_DEFAULT_LDC_SWITCHES': '',
    'LIB_SUFFIX': '',
    'OPTIONAL_COMPILER_RT_DIR': '',
    'COMMON_CONF_LINES': '',
}

ldc2_druntime_cfg_data = configuration_data(common_cfg_dict)

ldc2_druntime_cfg_data.set('CONF_IMPORTS', '"-Iruntime/druntime/src", "-I'+tagged_include_dir+'/"')
ldc2_druntime_cfg_data.set('CMAKE_BINARY_DIR', druntime_tgt[0].full_path()) #unused
ldc2_druntime_cfg_data.set('SHARED_LIBS_RPATH', druntime_tgt[0].full_path()) #unused

ldc2_druntime_conf = configure_file(
    input: 'ldc2.conf.in',
    configuration: ldc2_druntime_cfg_data,
    output: 'ldc2_druntime.conf',
)

install_subdir('runtime/druntime/src', install_dir: 'import')
install_subdir(tagged_include_dir, strip_directory: true, install_dir: 'import/tagged')

phobos_tgt = custom_target('phobos_tgt',
    output: phobos_tgts,
    depends: druntime_tgt,
    command :
    [
        cmake,
        phobos_ninja_target, #ninja target, FIXME: must be able to build both targets simultaneously
        '@OUTDIR@', #copy target to this dir
        '-S', '@CURRENT_SOURCE_DIR@' / 'runtime',
        '-B', '@PRIVATE_DIR@',
        '-D', 'D_EXTRA_FLAGS='+d_args_semi+';--d-version=GENERIC_IO;-conf='+ldc2_druntime_conf.full_path(),
    ] + base_opts,
    install: true,
    install_dir: 'lib',
)

install_subdir('runtime/phobos', install_dir: 'import')

etc_cfg_data = configuration_data(common_cfg_dict)
etc_cfg_data.set('CONF_IMPORTS', '"-I%%ldcconfigpath%%/../import/src/", "-I%%ldcconfigpath%%/../import/tagged/", "-I%%ldcconfigpath%%/../import/phobos/"')
etc_cfg_data.set('ADDITIONAL_DEFAULT_LDC_SWITCHES', '"-defaultlib=druntime-ldc,phobos2-ldc"')
etc_cfg_data.set('CMAKE_BINARY_DIR', '.')
etc_cfg_data.set('SHARED_LIBS_RPATH', 'lib/')

ldc2_conf = configure_file(
    input: 'ldc2.conf.in',
    configuration: etc_cfg_data,
    output: 'ldc2_tagged.conf',
    install: true,
    install_dir: 'etc',
)

#~ firmware = executable(
#~     'firmware.elf',
#~     dependencies: [
#~         d_dep,
#~         hardware_interface_dep,
#~         picolibc_dep,
#~         libunwind_dep,
#~     ],
#~     link_with: [
#~         semihost_lib,
#~     ],
#~     link_language: 'c',
#~     link_depends: linker_script,
#~     link_args: [
#~         '-static',
#~         '-Xlinker', '--script=' + linker_script.get(0).full_path(),
#~         '-L'+path_to_math_lib[0], '-l'+path_to_math_lib[1],
#~     ]
#~ )

#~ test(
#~     'unittests',
#~     firmware,
#~ )
