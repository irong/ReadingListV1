platform :ios, '11.0'
use_frameworks!

target 'ReadingList' do
  pod 'SVProgressHUD', '~> 2.2'
  pod 'CHCSVParser', :git => 'https://github.com/davedelong/CHCSVParser.git'
  # Seeme that we need to include Promises as a Pod rather than a Swift package, as it is also
  # used by Firebase, and we end up with two copies of the library if we include it as a Swift
  # packages; this was causing some crashes during development.
  pod 'PromisesSwift', '~> 1.2'
  pod 'Firebase/Crashlytics'
  pod 'Firebase/Analytics'

  target 'ReadingList_UnitTests' do
    inherit! :complete
  end
  target 'ReadingList_UITests' do
    inherit! :complete
  end

end
