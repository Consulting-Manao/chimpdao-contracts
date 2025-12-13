//
//  NFTView.swift
//  Chimp
//
//  View for displaying NFT metadata and image
//

import UIKit

class NFTView: UIViewController {
    private var metadata: NFTMetadata?
    private var imageData: Data?

    // UI Elements
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let nftImageView = UIImageView()
    private let nameLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let ownerLabel = UILabel()
    private let attributesStackView = UIStackView()
    private let loadingIndicator = UIActivityIndicatorView(style: .large)
    private let errorLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    private func setupUI() {
        view.backgroundColor = .systemBackground
        title = "NFT Details"

        // Setup scroll view
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentView)

        // Setup image view
        nftImageView.contentMode = .scaleAspectFit
        nftImageView.layer.cornerRadius = 12
        nftImageView.layer.masksToBounds = true
        nftImageView.backgroundColor = .systemGray6
        nftImageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(nftImageView)

        // Setup name label
        nameLabel.font = .systemFont(ofSize: 24, weight: .bold)
        nameLabel.textAlignment = .center
        nameLabel.numberOfLines = 0
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(nameLabel)

        // Setup description label
        descriptionLabel.font = .systemFont(ofSize: 16, weight: .regular)
        descriptionLabel.textColor = .secondaryLabel
        descriptionLabel.textAlignment = .center
        descriptionLabel.numberOfLines = 0
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(descriptionLabel)

        // Setup owner label
        ownerLabel.font = .systemFont(ofSize: 14, weight: .medium)
        ownerLabel.textColor = .systemBlue
        ownerLabel.textAlignment = .center
        ownerLabel.numberOfLines = 0
        ownerLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(ownerLabel)

        // Setup attributes stack view
        attributesStackView.axis = .vertical
        attributesStackView.spacing = 8
        attributesStackView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(attributesStackView)

        // Setup loading indicator
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.hidesWhenStopped = true
        contentView.addSubview(loadingIndicator)

        // Setup error label
        errorLabel.font = .systemFont(ofSize: 16, weight: .regular)
        errorLabel.textColor = .systemRed
        errorLabel.textAlignment = .center
        errorLabel.numberOfLines = 0
        errorLabel.isHidden = true
        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(errorLabel)

        // Layout constraints
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            loadingIndicator.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            errorLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            errorLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            errorLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            errorLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            nftImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            nftImageView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            nftImageView.widthAnchor.constraint(equalToConstant: 300),
            nftImageView.heightAnchor.constraint(equalToConstant: 300),

            nameLabel.topAnchor.constraint(equalTo: nftImageView.bottomAnchor, constant: 20),
            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            descriptionLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 12),
            descriptionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            descriptionLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            ownerLabel.topAnchor.constraint(equalTo: descriptionLabel.bottomAnchor, constant: 8),
            ownerLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            ownerLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            attributesStackView.topAnchor.constraint(equalTo: ownerLabel.bottomAnchor, constant: 20),
            attributesStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            attributesStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            attributesStackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20)
        ])
    }

    /// Display NFT data
    /// - Parameters:
    ///   - metadata: NFT metadata
    ///   - imageData: NFT image data
    ///   - ownerAddress: Owner address (optional)
    func displayNFT(metadata: NFTMetadata, imageData: Data?, ownerAddress: String? = nil) {
        self.metadata = metadata
        self.imageData = imageData

        DispatchQueue.main.async {
            self.loadingIndicator.stopAnimating()
            self.errorLabel.isHidden = true

            // Set image
            if let imageData = imageData, let image = UIImage(data: imageData) {
                self.nftImageView.image = image
            } else {
                // Placeholder image
                self.nftImageView.image = UIImage(systemName: "photo")
                self.nftImageView.tintColor = .systemGray
            }

            // Set metadata
            self.nameLabel.text = metadata.name ?? "Unnamed NFT"
            self.descriptionLabel.text = metadata.description ?? "No description available"

            // Set owner address
            if let ownerAddress = ownerAddress {
                self.ownerLabel.text = "Owner: \(ownerAddress)"
                self.ownerLabel.isHidden = false
            } else {
                self.ownerLabel.isHidden = true
            }

            // Clear existing attributes
            self.attributesStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

            // Add attributes
            if let attributes = metadata.attributes, !attributes.isEmpty {
                let attributesTitle = UILabel()
                attributesTitle.text = "Attributes"
                attributesTitle.font = .systemFont(ofSize: 18, weight: .semibold)
                attributesTitle.textAlignment = .center
                self.attributesStackView.addArrangedSubview(attributesTitle)

                for attribute in attributes {
                    let attributeView = self.createAttributeView(traitType: attribute.trait_type, value: attribute.value)
                    self.attributesStackView.addArrangedSubview(attributeView)
                }
            }
        }
    }

    /// Show loading state
    func showLoading() {
        DispatchQueue.main.async {
            self.loadingIndicator.startAnimating()
            self.errorLabel.isHidden = true
            self.nftImageView.image = nil
            self.nameLabel.text = ""
            self.descriptionLabel.text = ""
            self.ownerLabel.text = ""
            self.ownerLabel.isHidden = true
            self.attributesStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        }
    }

    /// Show error state
    /// - Parameter error: Error message
    func showError(_ error: String) {
        DispatchQueue.main.async {
            self.loadingIndicator.stopAnimating()
            self.errorLabel.text = error
            self.errorLabel.isHidden = false
            self.nftImageView.image = nil
            self.nameLabel.text = ""
            self.descriptionLabel.text = ""
            self.ownerLabel.text = ""
            self.ownerLabel.isHidden = true
            self.attributesStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        }
    }

    private func createAttributeView(traitType: String, value: String) -> UIView {
        let container = UIView()
        container.backgroundColor = .systemGray6
        container.layer.cornerRadius = 8
        container.layer.masksToBounds = true

        let traitLabel = UILabel()
        traitLabel.text = traitType
        traitLabel.font = .systemFont(ofSize: 14, weight: .medium)
        traitLabel.textColor = .secondaryLabel
        traitLabel.translatesAutoresizingMaskIntoConstraints = false

        let valueLabel = UILabel()
        valueLabel.text = value
        valueLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        valueLabel.textAlignment = .center
        valueLabel.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(traitLabel)
        container.addSubview(valueLabel)

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 60),

            traitLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            traitLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            traitLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),

            valueLabel.topAnchor.constraint(equalTo: traitLabel.bottomAnchor, constant: 2),
            valueLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            valueLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            valueLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8)
        ])

        return container
    }
}
