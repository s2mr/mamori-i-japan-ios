//
//  Tutorial1ViewController.swift
//  TraceCovid19
//
//  Created by yosawa on 2020/04/09.
//

import UIKit

final class Tutorial1ViewController: UIViewController, NavigationBarHiddenApplicapable, Agreement1Accessable {
    @IBAction func tappedNextButton(_ sender: Any) {
        pushToAgreement1()
    }

    @IBAction func tappedHelpButton(_ sender: Any) {
        // TODO: URL
        showAlert(message: "URLを設定して必要な情報に誘導します")
    }
}
