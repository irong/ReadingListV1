platform :ios, '11.0'
use_frameworks!

target 'ReadingList' do
  pod 'DZNEmptyDataSet', '~> 1.8'
  pod 'SwiftyJSON', '~> 5.0'
  pod 'Eureka', '~> 5.0'
  pod 'ImageRow', :git => 'https://github.com/EurekaCommunity/ImageRow.git', :commit => '296d79b'
  pod 'SVProgressHUD', '~> 2.2'
  pod 'SwiftyStoreKit', '~> 0.13'
  pod 'CHCSVParser', :git => 'https://github.com/davedelong/CHCSVParser.git'
  pod 'PromisesSwift', '~> 1.2'
  pod 'SimulatorStatusMagic', :configurations => ['Debug']
  pod 'Fabric'
  pod 'Crashlytics'
  pod 'Firebase/Core'

  target 'ReadingList_UnitTests' do
    inherit! :complete
    pod 'SwiftyJSON', '~> 5.0'
    pod 'Swifter', :git => 'https://github.com/httpswift/swifter.git', :commit => '7e07b39034dcaf095e62ab51c35486d361cd8b1e'
  end
  target 'ReadingList_UITests' do
    inherit! :complete
    pod 'Swifter', :git => 'https://github.com/httpswift/swifter.git', :commit => '7e07b39034dcaf095e62ab51c35486d361cd8b1e'
  end
  target 'ReadingList_Screenshots' do
    inherit! :complete
    pod 'Swifter', :git => 'https://github.com/httpswift/swifter.git', :commit => '7e07b39034dcaf095e62ab51c35486d361cd8b1e'
  end

  # Remove an Xcode warning about automatically settings build architecture
  post_install do |installer|
    installer.pods_project.targets.each do |target|
      target.build_configurations.each do |config|
        config.build_settings.delete 'ARCHS'
      end
    end
  end

end
