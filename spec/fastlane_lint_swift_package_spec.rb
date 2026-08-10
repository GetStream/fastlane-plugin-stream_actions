describe Fastlane do
  describe Fastlane::FastFile do
    describe 'Lint Swift Package Action' do
      let(:package_path) { 'Package.swift' }

      after do
        FileUtils.rm_f(package_path)
      end

      def lint
        described_class.new.parse("lane :test do
          lint_swift_package(swift_package_path: '../#{package_path}')
        end").runner.execute(:test)
      end

      def write_package(dependencies)
        File.write(package_path, <<~SWIFT)
        // swift-tools-version:5.9
        import PackageDescription

        let package = Package(
            name: "StreamChat",
            dependencies: [
        #{dependencies}
            ],
            targets: [
                .target(name: "StreamChat", dependencies: [.product(name: "NIO", package: "swift-nio")])
            ]
        )
        SWIFT
      end

      it 'passes when all dependencies are pinned with from or exact' do
        write_package(<<~DEPS)
            .package(url: "https://github.com/apple/swift-nio.git", from: "2.0.0"),
            .package(url: "https://github.com/GetStream/stream-core-swift.git", exact: "1.2.3"),
            .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", .upToNextMajor(from: "1.0.0"))
        DEPS

        expect { lint }.not_to raise_error
      end

      it 'fails when a dependency points to a branch' do
        write_package('.package(url: "https://github.com/apple/swift-nio.git", branch: "main")')

        expect { lint }.to raise_error(/branch-based dependency/)
      end

      it 'fails when a dependency uses the legacy branch requirement' do
        write_package('.package(url: "https://github.com/apple/swift-nio.git", .branch("main"))')

        expect { lint }.to raise_error(/branch-based dependency/)
      end

      it 'fails when a dependency is pinned to a revision' do
        write_package('.package(url: "https://github.com/apple/swift-nio.git", revision: "f1c2d3e")')

        expect { lint }.to raise_error(/revision-pinned dependency/)
      end

      it 'fails when a dependency uses a version range' do
        write_package('.package(url: "https://github.com/apple/swift-nio.git", "1.0.0"..<"2.0.0")')

        expect { lint }.to raise_error(/version-range dependency/)
      end

      it 'fails when a dependency uses upToNextMinor' do
        write_package('.package(url: "https://github.com/apple/swift-nio.git", .upToNextMinor(from: "1.0.0"))')

        expect { lint }.to raise_error(/version-range dependency/)
      end

      it 'fails when a dependency uses a local path' do
        write_package('.package(path: "../stream-core-swift")')

        expect { lint }.to raise_error(/local path dependency/)
      end

      it 'fails when a dependency url is not https' do
        write_package('.package(url: "git@github.com:apple/swift-nio.git", from: "2.0.0")')

        expect { lint }.to raise_error(/insecure or non-https url/)
      end

      it 'fails when a dependency has no version requirement' do
        write_package('.package(url: "https://github.com/apple/swift-nio.git")')

        expect { lint }.to raise_error(/missing version requirement/)
      end

      it 'fails when a dependency is declared twice' do
        write_package(<<~DEPS)
            .package(url: "https://github.com/apple/swift-nio.git", from: "2.0.0"),
            .package(url: "https://github.com/Apple/swift-nio", exact: "2.1.0")
        DEPS

        expect { lint }.to raise_error(/duplicate dependency/)
      end

      it 'reports all issues at once' do
        write_package(<<~DEPS)
            .package(url: "https://github.com/apple/swift-nio.git", branch: "main"),
            .package(url: "https://github.com/GetStream/stream-core-swift.git", revision: "f1c2d3e")
        DEPS

        expect { lint }.to raise_error(/2 dependency issue\(s\)/)
      end

      it 'fails when Package.swift does not exist' do
        expect { lint }.to raise_error(/Package.swift not found/)
      end
    end
  end
end
