platform :osx, '10.14'

target 'Maccy' do
  use_frameworks!

  pod 'Fuse', '~> 1.4'
  pod 'KeyboardShortcuts', git: 'https://github.com/gpoitch/KeyboardShortcuts.git', branch: 'gp/default-shortcuts'
  pod 'LoginServiceKit', git: 'https://github.com/Clipy/LoginServiceKit.git'
  pod 'Preferences', '~> 1.0'
  pod 'Sparkle', '~> 1.21'
  pod 'Sauce', '~> 2.1' # Needed for migration to KeyboardShortcuts
  pod 'SwiftHEXColors', '~> 1.3'

  target 'MaccyTests' do
    inherit! :search_paths
  end
end
