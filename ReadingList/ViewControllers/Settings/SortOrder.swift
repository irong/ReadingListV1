import Foundation
import Eureka

final class SortOrder: FormViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        form +++ Section(header: "Sort Options", footer: """
            Configure whether newly added books get added to the top or the bottom of the \
            reading list when Custom ordering is used.
            """)
            <<< SwitchRow {
                $0.title = "Add Books to Top"
                $0.value = UserDefaults.standard[.addBooksToTopOfCustom]
                $0.onChange {
                    UserDefaults.standard[.addBooksToTopOfCustom] = $0.value ?? false
                }
            }
        monitorThemeSetting()
    }
}
