Pod::Spec.new do |s|
  s.name             = 'DecentriLicense'
  s.version          = '0.1.0'
  s.summary          = 'DecentriLicense native static library for iOS (dl-core + OpenSSL + libcurl combined)'
  s.homepage         = 'https://example.com/decentrilicense'
  s.license          = { :type => 'Proprietary' }
  s.author           = { 'CipherSheet' => 'dev@example.com' }
  s.source           = { :path => '.' }
  s.platform         = :ios, '13.0'
  s.requires_arc     = false

  # preserve_paths 保证文件被复制进 Pods 目录；不用 vendored_libraries 避免两库同时被 link
  s.preserve_paths = 'libdecentrilicense-device.a', 'libdecentrilicense-simulator.a'

  s.pod_target_xcconfig = {
    'CLANG_CXX_LIBRARY' => 'libc++',
  }

  # 关键：用 -force_load 保留所有符号，防止 FFI 运行时查找的符号被 dead-strip。
  # 同时按 SDK 选不同 fat archive。下面在 user_target_xcconfig 里给 Runner 主项目加。
  s.user_target_xcconfig = {
    # PODS_ROOT 在 Pods-Runner xcconfig 里可见；pod install 后我们把 .a 复制到 Pods/DecentriLicense/
    'OTHER_LDFLAGS[sdk=iphoneos*]'        => '$(inherited) -force_load "$(PODS_ROOT)/DecentriLicense/libdecentrilicense-device.a" -lc++ -lz -framework Security',
    'OTHER_LDFLAGS[sdk=iphonesimulator*]' => '$(inherited) -force_load "$(PODS_ROOT)/DecentriLicense/libdecentrilicense-simulator.a" -lc++ -lz -framework Security',
  }

  s.frameworks = 'Security', 'Foundation'
  s.libraries  = 'c++', 'z'
end
