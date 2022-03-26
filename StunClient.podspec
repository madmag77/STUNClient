Pod::Spec.new do |s|
  s.name = 'StunClient'
  s.version = '1.0.4'
  s.license = 'MIT'
  s.summary = 'My IP address and port discovery'
  s.homepage = 'https://github.com/madmag77/StunClient'
  s.authors = { 'madmag77' => 'https://github.com/madmag77' }
  s.source = { :git => 'https://github.com/madmag77/StunClient.git', :tag => s.version }
  s.documentation_url = 'https://github.com/madmag77/StunClient'

  s.ios.deployment_target = '10.0'
  s.osx.deployment_target = '10.12'

  s.swift_versions = ['5.2']

  s.source_files = 'Sources/StunClient/**/*.swift'

  s.dependency 'SwiftNIO', '~> 2.38'
end
