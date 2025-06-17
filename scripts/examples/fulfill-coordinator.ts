import hre, { ethers } from "hardhat";
import { BigNumberish, ContractReceipt, utils } from "ethers";
import { NativeVRF, NativeVRF__factory, NativeVRFCoordinator__factory } from "../../typechain";
import addressUtils from "../../utils/addressUtils";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

const delay = (delayMs: number) => {
    return new Promise((resolve) => {
        setTimeout(() => {
            resolve(null);
        }, delayMs);
    })
}

const runInterval = async (handler: Function, delayMs: number) => {
    await handler();
    await delay(delayMs);
    await runInterval(handler, delayMs);
}

const messageHashFromNumbers = (values: BigNumberish[]) => {
    const types = values.map(() => "uint256");
    return ethers.utils.solidityKeccak256(types, values);
}

const convertSignatureLocal = (signature: utils.BytesLike) => {
    const truncatedNumber = ethers.BigNumber.from(signature).toHexString().slice(0, 66);
    return ethers.BigNumber.from(truncatedNumber);
}

const calculateRandomInput = async (signer: SignerWithAddress, nativeVRF: NativeVRF, requestId: string) => {
    let input = 0;
    let found = 0;

    const prevRandom = await nativeVRF.randomResults(Number(requestId) - 1);
    const difficulty = await nativeVRF.difficulty();

    do {
        const message = messageHashFromNumbers([prevRandom, input]);
        const signature = await signer.signMessage(ethers.utils.arrayify(message));
        const value = convertSignatureLocal(signature);

        if (value.mod(difficulty).eq(0)) {
            found = input;
        }

        input++;
    } while (found === 0);

    const message = messageHashFromNumbers([prevRandom, found]);
    const signature = await signer.signMessage(ethers.utils.arrayify(message));

    return { input: found, signature };
}

const decordOutputs = (receipt: ContractReceipt) => {
    const events = receipt.events;
    if (!events) return [];
    return events.filter(e => e.event).map(e => [e.event, e.args]);
}

async function main() {
    const addressList = await addressUtils.getAddressList(hre.network.name);

    const [signer] = await ethers.getSigners();
    
    // Connect to the coordinator instead of directly to NativeVRF
    const coordinator = NativeVRFCoordinator__factory.connect(addressList['NativeVRFCoordinator'], signer);
    
    // Get the NativeVRF address from the coordinator
    const nativeVRFAddress = await coordinator.nativeVRF();
    const nativeVRF = NativeVRF__factory.connect(nativeVRFAddress, signer);

    const delayMs = 1000;

    runInterval(async () => {
        try {
            const curRequestId = await nativeVRF.currentRequestId();
            const latestFulfill = await nativeVRF.latestFulfillId();
            const requestId = latestFulfill.add(1);

            if (curRequestId.eq(requestId)) {
                console.log("There is no new random request. Wait for the incoming requests...");
                return;
            }

            // Check if this request is registered in the coordinator
            const requestConfig = await coordinator.requestConfigs(requestId);
            if (requestConfig.consumer === ethers.constants.AddressZero) {
                console.log(`Request ${requestId} not registered in coordinator, skipping...`);
                return;
            }
            
            // Check if the request has already been fulfilled
            if (requestConfig.fulfilled) {
                console.log(`Request ${requestId} already fulfilled, skipping...`);
                return;
            }

            console.log("Found new random request");
            console.log('Current ID: ', curRequestId.toString(), 'Last fulfill ID', latestFulfill.toString(), 'Submitted Fulfill ID: ', requestId.toString());
            console.log('Consumer: ', requestConfig.consumer);

            const { input, signature } = await calculateRandomInput(
                signer,
                nativeVRF,
                requestId.toString(),
            );

            // Use the coordinator to fulfill randomness
            const tx = await coordinator.fulfillRandomness(requestId, input, signature);

            console.log("Submit fulfill transaction");

            const receipt = await tx.wait();

            console.log("Fulfill randomness successfully");
            console.log("Data: ", decordOutputs(receipt));
            
            // Calculate and display profit information
            const gasUsed = receipt.gasUsed;
            const gasPrice = receipt.effectiveGasPrice;
            const cost = gasUsed.mul(gasPrice);
            
            // Get the payment from the RequestFulfilled event
            const fulfillEvent = receipt.events?.find(e => e.event === 'RequestFulfilled');
            const payment = fulfillEvent?.args?.payment;
            
            if (payment) {
                const profit = payment.sub(cost);
                console.log(`Gas used: ${gasUsed.toString()}`);
                console.log(`Gas price: ${ethers.utils.formatUnits(gasPrice, 'gwei')} gwei`);
                console.log(`Cost: ${ethers.utils.formatEther(cost)} ETH`);
                console.log(`Payment: ${ethers.utils.formatEther(payment)} ETH`);
                console.log(`Profit: ${ethers.utils.formatEther(profit)} ETH`);
            }
        } catch (e) {
            console.error("Error fulfill randomness", e);
        }
    }, delayMs);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
