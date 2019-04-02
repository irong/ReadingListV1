platform :ios, '11.0'
use_frameworks!

target 'ReadingList' do
  pod 'DZNEmptyDataSet', '~> 1.8'
  pod 'SwiftyJSON', '~> 4.0'
  pod 'Eureka', '~> 5.0'
  pod 'ImageRow', :git => 'https://github.com/AndrewBennet/ImageRow.git'
  pod 'SVProgressHUD', '~> 2.2'
  pod 'SwiftyStoreKit', '~> 0.13'
  pod 'CHCSVParser', :git => 'https://github.com/davedelong/CHCSVParser.git'
  pod 'PromisesSwift', '~> 1.2'
  pod 'SimulatorStatusMagic', :configurations => ['Debug']
  pod 'Swifter', '1.4.5', :configurations => ['Debug']
  pod 'Fabric'
  pod 'Crashlytics'
  pod 'Firebase/Core'

  target 'ReadingList_UnitTests' do
    inherit! :complete
    pod 'SwiftyJSON', '~> 4.0'
  end
  target 'ReadingList_UITests' do
    inherit! :complete
  end
  target 'ReadingList_Screenshots' do
    inherit! :complete
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
