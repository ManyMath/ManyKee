Pod::Spec.new do |s|
  s.name             = 'keepass_flutter'
  s.version          = '0.1.0'
  s.summary          = 'Flutter plugin for KeePass KDBX support'
  s.homepage         = 'https://github.com/AnyManyKey/manykee'
  s.license          = { :type => 'MIT' }
  s.author           = { 'ManyKee' => 'dev@manykee.com' }
  s.source           = { :path => '.' }
  s.dependency 'Flutter'
  s.platform = :ios, '12.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
