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
#~         '-D', 'CMAKE_C_FLAGS=-target thumbv7em-unknown-none-eabi -fshort-enums', #FIXME: replace triple and options
#~         '-D', 'CMAKE_EXE_LINKER_FLAGS="-target thumbv7em-unknown-none-eabi --no-standard-libraries"',
        '-D', 'BUILD_SHARED_LIBS=OFF',
        '-D', 'C_SYSTEM_LIBS=',
        '-D', 'TARGET_SYSTEM=freertos_arm',
        '-D', 'EXTERNAL_TAGS=freertos,default_abort',
]

druntime_tgt = custom_target('druntime_tgt',
    output:
    [
        'libdruntime-ldc.a',
    ],
    command :
    [
        cmake,
        '-S', '@CURRENT_SOURCE_DIR@' / 'runtime',
        '-B', '@OUTDIR@',
        '-D', 'D_EXTRA_FLAGS=--mtriple=thumbv7em-unknown-none-eabi;--fthread-model=local-exec;-conf=;--d-version=GENERIC_IO;--verrors=0',
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
conf_data.set('CONF_IMPORTS', '-Iruntime/druntime/src, -Iimport/tagged_imports/freertos_arm/')
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
        '-S', '@CURRENT_SOURCE_DIR@' / 'runtime',
        '-B', '@OUTDIR@',
        '-D', 'D_EXTRA_FLAGS=--mtriple=thumbv7em-unknown-none-eabi;--fthread-model=local-exec;-conf='+ldc2_druntime_conf.full_path()+';--d-version=GENERIC_IO;--verrors=0',
    ] + base_opts,
)

phobos_dep = declare_dependency(
    link_with: phobos_tgt,
)

phobos_static_lib = static_library(
    'phobos',
    dependencies: [
        druntime_dep,
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
