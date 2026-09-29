#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint linklab_flutter_sdk.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'linklab_flutter_sdk'
  s.version          = '0.4.0'
  s.summary          = 'Flutter plugin for Linklab dynamic links and deferred deep linking.'
  s.description      = <<-DESC
Flutter plugin for the Linklab deep linking service: universal links, deferred deep links
(pasteboard / IP attribution) and short-link resolution, bridged to the Linklab iOS SDK.
                       DESC
  s.homepage         = 'https://linklab.cc'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Linklab' => 'info@linklab.cc' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.dependency 'Linklab', '~> 0.3.0'
  s.platform = :ios, '14.3'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.9'
end
