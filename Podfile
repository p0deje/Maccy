platform :osx, '10.14'

target 'Maccy' do
  use_frameworks!

  pod 'Fuse', '~> 1.2'
  pod 'KeyHolder', git: 'https://github.com/Clipy/KeyHolder.git'
  pod 'LoginServiceKit', git: 'https://github.com/Clipy/LoginServiceKit.git'
  pod 'Magnet', '~> 3.2'
  pod 'Preferences', '~> 1.0'
  pod 'Sparkle', '~> 1.21'
  pod 'SwiftHEXColors', '~> 1.3'

  target 'MaccyTests' do
    inherit! :search_paths
  end

  # Workaround to be able to view KeyHolder inside Interface Builder.
  # https://github.com/Clipy/KeyHolder/issues/6
  # https://github.com/CocoaPods/CocoaPods/issues/5334#issuecomment-255831772
  post_install do |installer|
    installer.pods_project.build_configurations.each do |config|
      config.build_settings['LD_RUNPATH_SEARCH_PATHS'] = [
        '$(FRAMEWORK_SEARCH_PATHS)'
      ]
    end
  end
end
