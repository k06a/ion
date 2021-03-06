// Copyright (c) 2018 Clearmatics Technologies Ltd
package contract

import (
	"context"
	"crypto/ecdsa"
	"log"
	"math/big"
	"os"

	"github.com/ethereum/go-ethereum/accounts/abi/bind"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/common/compiler"
	"github.com/ethereum/go-ethereum/core/types"
)

// CompileAndDeployTriggerVerifierAndConsumerFunction method
func CompileAndDeployTriggerVerifierAndConsumerFunction(
	ctx context.Context,
	client bind.ContractBackend,
	userKey *ecdsa.PrivateKey,
	ionContractAddress common.Address,
) <-chan ContractInstance {
	// ---------------------------------------------
	// COMPILE VALIDATION AND DEPENDENCIES
	// ---------------------------------------------
	basePath := os.Getenv("GOPATH") + "/src/github.com/clearmatics/ion/contracts/"
	triggerEventVerifierContractPath := basePath + "TriggerEventVerifier.sol"
	consumerFunctionContractPath := basePath + "Function.sol"

	contracts, err := compiler.CompileSolidity("", consumerFunctionContractPath, triggerEventVerifierContractPath)
	if err != nil {
		log.Fatal("ERROR failed to compile TriggerEventVerifier.sol:", err)
	}

	triggerEventVerifierContract := contracts[triggerEventVerifierContractPath+":TriggerEventVerifier"]
	triggerEventVerifierBinStr, triggerEventVerifierABIStr := getContractBytecodeAndABI(triggerEventVerifierContract)
	consumerFunctionContract := contracts[consumerFunctionContractPath+":Function"]
	consumerFunctionBinStr, consumerFunctionABIStr := getContractBytecodeAndABI(consumerFunctionContract)

	// ---------------------------------------------
	// DEPLOY TRIGGER EVENT CONTRACT
	// ---------------------------------------------
	triggerEventSignedTx := compileAndDeployContract(
		ctx,
		client,
		userKey,
		triggerEventVerifierBinStr,
		triggerEventVerifierABIStr,
		nil,
		uint64(3000000),
	)

	resChan := make(chan ContractInstance)

	// Go-Routine that waits for PatriciaTrie Library and Ion Contract to be deployed
	// Ion depends on PatriciaTrie library
	go func() {
		defer close(resChan)
		deployBackend := client.(bind.DeployBackend)

		// wait for trigger event contract to be deployed
		triggerEventAddr, err := bind.WaitDeployed(ctx, deployBackend, triggerEventSignedTx)
		if err != nil {
			log.Fatal("ERROR while waiting for contract deployment")
		}

		// ---------------------------------------------
		// DEPLOY CONSUMER FUNCTION CONTRACT
		// ---------------------------------------------
		consumerFunctionSignedTx := compileAndDeployContract(
			ctx,
			client,
			userKey,
			consumerFunctionBinStr,
			consumerFunctionABIStr,
			nil,
			uint64(3000000),
			ionContractAddress,
			triggerEventAddr,
		)

		resChan <- ContractInstance{triggerEventVerifierContract, triggerEventAddr}

		// wait for consumer function contract to be deployed
		consumerFunctionAddr, err := bind.WaitDeployed(ctx, deployBackend, consumerFunctionSignedTx)
		if err != nil {
			log.Fatal("ERROR while waiting for contract deployment")
		}

		resChan <- ContractInstance{consumerFunctionContract, consumerFunctionAddr}
	}()

	return resChan
}

func VerifyExecute(
	ctx context.Context,
	backend bind.ContractBackend,
	userKey *ecdsa.PrivateKey,
	contract *compiler.Contract,
	toAddr common.Address,
	chainId common.Hash,
	blockHash common.Hash,
	txTriggerTo common.Address,
	txTriggerPath []byte,
	txTriggerRLP []byte,
	txTriggerProofArr []byte,
	receiptTrigger []byte,
	receiptTriggerProofArr []byte,
	triggerCalledBy common.Address,
	amount *big.Int,

) (tx *types.Transaction) {
	tx = TransactionContract(
		ctx,
		backend,
		userKey,
		contract,
		toAddr,
		amount,
		uint64(3000000),
		"verifyAndExecute",
		chainId,
		blockHash,
		txTriggerTo,            // TRIG_DEPLOYED_RINKEBY_ADDR,
		txTriggerPath,          // TEST_PATH,
		txTriggerRLP,           // TEST_TX_VALUE,
		txTriggerProofArr,      // TEST_TX_NODES,
		receiptTrigger,         // TEST_RECEIPT_VALUE,
		receiptTriggerProofArr, // TEST_RECEIPT_NODES,
		triggerCalledBy,        // TRIG_CALLED_BY,
	)
	return
}
