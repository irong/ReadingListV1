platform :ios, '11.0'
use_frameworks!

target 'ReadingList' do
  pod 'SVProgressHUD', '~> 2.2'
  pod 'CHCSVParser', :git => 'https://github.com/davedelong/CHCSVParser.git'
  pod 'Fabric'
  pod 'Crashlytics'
  pod 'Firebase/Core'

  target 'ReadingList_UnitTests' do
    inherit! :complete
  end
  target 'ReadingList_UITests' do
    inherit! :complete
  end

end
