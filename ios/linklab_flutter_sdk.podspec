#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
#
Pod::Spec.new do |s|
  s.name             = 'linklab_flutter_sdk'
  s.version          = '0.1.4'
  s.summary          = 'Flutter SDK for LinkLab deep linking service'
  s.description      = <<-DESC
  A Flutter plugin for the LinkLab deep linking service. This plugin allows Flutter applications to handle dynamic links provided by LinkLab.
                       DESC
  s.homepage         = 'https://linklab.cc'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'LinkLab' => 'info@linklab.cc' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '14.3'

  # Add dependency to the LinkLab iOS SDK from CocoaPods
  s.dependency 'Linklab', '~> 0.1.4'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end