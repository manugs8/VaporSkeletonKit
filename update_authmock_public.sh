#!/bin/bash
cd ../AuthMock/Sources/AuthMockServer

# Make Config public
sed -i '' 's/struct Config:/public struct Config:/g' Config.swift
sed -i '' 's/    let port/    public let port/g' Config.swift
sed -i '' 's/    let status/    public let status/g' Config.swift
sed -i '' 's/    let issuer/    public let issuer/g' Config.swift
sed -i '' 's/    let audience/    public let audience/g' Config.swift
sed -i '' 's/    let expiresIn/    public let expiresIn/g' Config.swift
sed -i '' 's/    init(/    public init(/g' Config.swift

# Make Routes public
sed -i '' 's/func routes(/public func routes(/g' Routes.swift

# Make StatusOverrideBox public
sed -i '' 's/actor StatusOverrideBox/public actor StatusOverrideBox/g' StatusOverrideBox.swift
sed -i '' 's/    init()/    public init()/g' StatusOverrideBox.swift
sed -i '' 's/    func arm/    public func arm/g' StatusOverrideBox.swift
sed -i '' 's/    func consume/    public func consume/g' StatusOverrideBox.swift

# Make ClaimsOverrideBox public
sed -i '' 's/actor ClaimsOverrideBox/public actor ClaimsOverrideBox/g' ClaimsOverrideBox.swift
sed -i '' 's/struct ClaimsOverride/public struct ClaimsOverride/g' ClaimsOverrideBox.swift
sed -i '' 's/    init()/    public init()/g' ClaimsOverrideBox.swift
sed -i '' 's/    func arm/    public func arm/g' ClaimsOverrideBox.swift
sed -i '' 's/    func consume/    public func consume/g' ClaimsOverrideBox.swift


cd ../AuthMock/Sources/AuthMockServer
sed -i '' 's/    let sub:/    public let sub:/g' ClaimsOverrideBox.swift
sed -i '' 's/    let permissions:/    public let permissions:/g' ClaimsOverrideBox.swift
cat << 'INNEREOF' >> ClaimsOverrideBox.swift

extension ClaimsOverride {
    public init(sub: String? = nil, permissions: [String]? = nil) {
        self.sub = sub
        self.permissions = permissions
    }
}
INNEREOF
