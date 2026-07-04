Pod::Spec.new do |s|
  s.name             = 'keepass_flutter'
  s.version          = '0.1.0'
  s.summary          = 'Flutter plugin for KeePass KDBX support'
  s.homepage         = 'https://github.com/AnyManyKey/manykee'
  s.license          = { :type => 'MIT' }
  s.author           = { 'ManyKee' => 'dev@manykee.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'

  # Build the keepass_flutter_native Rust crate (static lib) via cargokit
  # and force-link it into the plugin framework. Mirrors the proven pattern
  # in pose_detector/packages/pose_flutter and soundboard's sound/microphone
  # plugins -- keeps cargokit itself unmodified.
  s.script_phase = {
    :name => 'Build keepass_flutter_native',
    :script => 'sh "$PODS_TARGET_SRCROOT/../cargokit/build_pod.sh" ../rust keepass_flutter_native',
    :execution_position => :before_compile,
    :input_files => ['${BUILT_PRODUCTS_DIR}/cargokit_phony'],
    :output_files => ['${BUILT_PRODUCTS_DIR}/libkeepass_flutter_native.a'],
  }

  s.platform = :osx, '10.14'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'OTHER_LDFLAGS' => '-force_load ${BUILT_PRODUCTS_DIR}/libkeepass_flutter_native.a',
  }
  s.swift_version = '5.0'
end
