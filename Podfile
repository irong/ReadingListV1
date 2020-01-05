platform :ios, '11.0'
use_frameworks!

target 'ReadingList' do
  pod 'Eureka', '~> 5.1'
  pod 'ImageRow', '~> 4.0'
  pod 'SVProgressHUD', '~> 2.2'
  pod 'CHCSVParser', :git => 'https://github.com/davedelong/CHCSVParser.git'
  pod 'Fabric'
  pod 'Crashlytics'
  pod 'Firebase/Core'

  target 'ReadingList_UnitTests' do
    inherit! :complete
    pod 'SwiftyJSON', '~> 5.0'
    pod 'Swifter', :git => 'https://github.com/httpswift/swifter.git', :branch => 'stable'
  end
  target 'ReadingList_UITests' do
    inherit! :complete
    pod 'Swifter', :git => 'https://github.com/httpswift/swifter.git', :branch => 'stable'
  end

end
