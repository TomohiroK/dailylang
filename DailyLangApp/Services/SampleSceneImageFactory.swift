import UIKit

enum SampleSceneImageFactory {
    private static let canvasSize = CGSize(width: 1200, height: 900)

    static func makeOfficeSceneImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: canvasSize)
        return renderer.image { context in
            UIColor.systemBackground.setFill()
            context.fill(CGRect(origin: .zero, size: canvasSize))

            drawHeader()
            drawDocumentCard()
            drawCoffeeCup()
            drawKeyboard()
        }
    }

    private static func drawHeader() {
        let title = "Daily Work Scene"
        title.draw(
            at: CGPoint(x: 80, y: 70),
            withAttributes: [
                .font: UIFont.systemFont(ofSize: 54, weight: .bold),
                .foregroundColor: UIColor.label,
            ]
        )
    }

    private static func drawDocumentCard() {
        let rect = CGRect(x: 80, y: 190, width: 660, height: 470)
        UIColor.secondarySystemBackground.setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: 28).fill()

        let lines = [
            "Invoice",
            "Meeting",
            "Bridge Note",
            "Coffee",
            "Laptop",
        ]

        for (index, line) in lines.enumerated() {
            line.draw(
                at: CGPoint(x: 130, y: 250 + (index * 70)),
                withAttributes: [
                    .font: UIFont.monospacedSystemFont(ofSize: 44, weight: .semibold),
                    .foregroundColor: UIColor.label,
                ]
            )
        }
    }

    private static func drawCoffeeCup() {
        let cupRect = CGRect(x: 830, y: 250, width: 220, height: 240)
        UIColor.systemBlue.withAlphaComponent(0.15).setFill()
        UIBezierPath(roundedRect: cupRect, cornerRadius: 36).fill()

        UIColor.systemBlue.setStroke()
        let cup = UIBezierPath(roundedRect: CGRect(x: 875, y: 320, width: 120, height: 120), cornerRadius: 18)
        cup.lineWidth = 12
        cup.stroke()

        let handle = UIBezierPath(arcCenter: CGPoint(x: 1010, y: 380), radius: 36, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: true)
        handle.lineWidth = 12
        handle.stroke()
    }

    private static func drawKeyboard() {
        let rect = CGRect(x: 220, y: 720, width: 760, height: 90)
        UIColor.tertiarySystemFill.setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: 18).fill()

        UIColor.systemGray3.setFill()
        for row in 0..<2 {
            for column in 0..<12 {
                let keyRect = CGRect(
                    x: 250 + (column * 56),
                    y: 738 + (row * 34),
                    width: 38,
                    height: 20
                )
                UIBezierPath(roundedRect: keyRect, cornerRadius: 5).fill()
            }
        }
    }
}

