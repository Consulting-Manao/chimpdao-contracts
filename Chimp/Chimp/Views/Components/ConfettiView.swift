import UIKit

/// Simple confetti animation view for success celebrations
class ConfettiView: UIView {
    private var emitterLayer: CAEmitterLayer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupConfetti()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupConfetti()
    }

    private func setupConfetti() {
        let emitter = CAEmitterLayer()
        // Position and size will be set in layoutSubviews
        emitter.emitterShape = .line
        emitter.birthRate = 0 // Start stopped

        // Create confetti particles
        var cells = [CAEmitterCell]()

        let colors: [UIColor] = [.systemBlue, .systemGreen, .systemPurple, .systemOrange, .systemPink]

        for (index, color) in colors.enumerated() {
            let cell = CAEmitterCell()
            cell.birthRate = 3.0 // More particles for better visibility
            cell.lifetime = 8.0 // Longer lifetime
            cell.velocity = 150 + CGFloat(index * 20) // Moderate fall speed
            cell.velocityRange = 50 // Less variation in speed
            cell.emissionLongitude = .pi // Straight down
            cell.emissionRange = .pi / 3 // Narrower spread (60 degrees) for more focused effect
            cell.spin = 1.5
            cell.spinRange = 2
            cell.scale = 0.25 // Much larger for better visibility
            cell.scaleRange = 0.15 // More consistent size
            cell.alphaSpeed = -0.06 // Slightly slower fade

            // Create larger colored shapes for better visibility
            let shapeSize = CGSize(width: 12, height: 12)
            UIGraphicsBeginImageContextWithOptions(shapeSize, false, 0)
            color.setFill()
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: shapeSize)).fill()
            let image = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()

            cell.contents = image?.cgImage
            cells.append(cell)
        }

        emitter.emitterCells = cells
        layer.addSublayer(emitter)
        emitterLayer = emitter
    }

    func startConfetti() {
        emitterLayer?.birthRate = 1.0

        // Stop after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.stopConfetti()
        }
    }

    func stopConfetti() {
        emitterLayer?.birthRate = 0
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Update emitter position and size when view bounds change
        emitterLayer?.emitterPosition = CGPoint(x: bounds.midX, y: bounds.minY - 20)
        emitterLayer?.emitterSize = CGSize(width: bounds.width * 1.5, height: 4)
    }
}

