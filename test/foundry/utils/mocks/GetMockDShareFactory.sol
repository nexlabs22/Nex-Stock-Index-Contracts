// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {DShareFactory} from "../../../../contracts/dinary/DShareFactory.sol";
import {DShare} from "../../../../contracts/dinary/DShare.sol";
import {WrappedDShare} from "../../../../contracts/dinary/WrappedDShare.sol";
import {TransferRestrictor} from "../../../../contracts/dinary/TransferRestrictor.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

library GetMockDShareFactory {
    function getMockDShareFactory(address owner) internal returns (DShareFactory, DShare, WrappedDShare) {
        DShare dShareImplementation = new DShare();
        WrappedDShare wrappedDShareImplementation = new WrappedDShare();

        DShareFactory dShareFactoryImplementation = new DShareFactory();
        DShareFactory dShareFactory = DShareFactory(
            address(
                new ERC1967Proxy(
                    address(dShareFactoryImplementation),
                    abi.encodeCall(
                        DShareFactory.initialize,
                        (
                            owner,
                            address(new UpgradeableBeacon(address(dShareImplementation), owner)),
                            address(new UpgradeableBeacon(address(wrappedDShareImplementation), owner)),
                            address(new TransferRestrictor(owner))
                        )
                    )
                )
            )
        );

        return (dShareFactory, dShareImplementation, wrappedDShareImplementation);
    }

    function deployDShare(DShareFactory factory, address owner, string memory name, string memory symbol)
        internal
        returns (DShare)
    {
        (address dshare,) = factory.createDShare(owner, name, symbol, "", "");
        return DShare(dshare);
    }
}
