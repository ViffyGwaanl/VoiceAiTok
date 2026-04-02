# VoiceTok Podfile
# VLCKit is distributed via CocoaPods (not SPM)

platform :ios, '17.0'
use_frameworks!
inhibit_all_warnings!

target 'VoiceTok' do
  # VLC Media Player Framework
  pod 'MobileVLCKit', '~> 3.6'

  # Note: WhisperKit is added via Swift Package Manager
  # in Xcode: File > Add Package Dependencies
  # URL: https://github.com/argmaxinc/WhisperKit.git
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
      config.build_settings['BUILD_LIBRARY_FOR_DISTRIBUTION'] = 'YES'
    end
  end
end
