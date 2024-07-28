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

base_opts = [
        '-G', 'Ninja',
        '-D', 'LDC_EXE_FULL=' + ldc2.full_path(),
        '-D', 'DMDFE_MINOR_VERSION=109',
        '-D', 'DMDFE_PATCH_VERSION=1',
        '-D', 'CMAKE_C_COMPILER=clang',
        '-D', 'CMAKE_SYSTEM_PROCESSOR='+host_machine.cpu_family(),
        '-D', 'CMAKE_SYSTEM_NAME=EXTERNAL',
        '-D', 'BUILD_SHARED_LIBS=OFF',
        '-D', 'C_SYSTEM_LIBS=',
        '-D', 'TARGET_SYSTEM=freertos_arm',
        '-D', 'EXTERNAL_TAGS=freertos,default_abort',
]

#FIXME: duplicates cross file settings
d_args_semi = '--mtriple=thumbv7em-unknown-none-eabi;--fthread-model=local-exec;--verrors=0'

druntime_tgt = custom_target('druntime_tgt',
    output:
    [
        'libdruntime-ldc.a',
    ],
    command :
    [
        cmake,
        'libdruntime-ldc.a', #ninja target
        '-S', '@CURRENT_SOURCE_DIR@' / 'runtime',
        '-B', '@OUTDIR@',
        '-D', 'D_EXTRA_FLAGS='+d_args_semi+';-conf=',
    ] + base_opts,
)

druntime_dep = declare_dependency(
    link_with: druntime_tgt,
)

druntime_static_lib = static_library(
    'druntime',
    dependencies: druntime_dep,
)

conf_data = configuration_data()
conf_data.set('ADDITIONAL_DEFAULT_LDC_SWITCHES', '')
conf_data.set('CONF_IMPORTS', '"-Iruntime/druntime/src", "-I'+meson.current_build_dir()+'/import/tagged_imports/freertos_arm/"')
conf_data.set('CMAKE_BINARY_DIR', druntime_tgt[0].full_path())
conf_data.set('LIB_SUFFIX', '')
conf_data.set('OPTIONAL_COMPILER_RT_DIR', '')
conf_data.set('SHARED_LIBS_RPATH', druntime_tgt[0].full_path())
conf_data.set('COMMON_CONF_LINES', '')

ldc2_druntime_conf = configure_file(
    input: 'ldc2.conf.in',
    configuration: conf_data,
    output: 'ldc2_druntime.conf',
)

phobos_tgt = custom_target('phobos_tgt',
    output:
    [
        'libphobos2-ldc.a',
    ],
    command :
    [
        cmake,
        'libphobos2-ldc.a', #ninja target name passed to wrapper as first CLI argument
        '-S', '@CURRENT_SOURCE_DIR@' / 'runtime',
        '-B', '@OUTDIR@',
        '-D', 'D_EXTRA_FLAGS='+d_args_semi+';--d-version=GENERIC_IO;-conf='+ldc2_druntime_conf.full_path(),
    ] + base_opts,
)

phobos_dep = declare_dependency(
    link_with: [
        phobos_tgt,
        druntime_tgt, # to provide tagged include/ for compilation
    ]
)

phobos_static_lib = static_library(
    'phobos',
    dependencies: [
        phobos_dep,
    ],
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
