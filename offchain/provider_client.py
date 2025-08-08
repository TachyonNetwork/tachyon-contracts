#!/usr/bin/env python3
import os
import time
import json
import subprocess
from web3 import Web3
from eth_account import Account
from eth_account.signers.local import LocalAccount

RPC_URL = os.getenv("RPC_URL", "http://localhost:8545")
PRIVATE_KEY = os.getenv("PRIVATE_KEY", "")
JOB_MANAGER = Web3.to_checksum_address(os.getenv("JOB_MANAGER", "0x0000000000000000000000000000000000000000"))
NODE_ADDRESS = Web3.to_checksum_address(os.getenv("NODE_ADDRESS", ""))
POLL_INTERVAL = int(os.getenv("POLL_INTERVAL", "10"))

# The provider client listens for recommended jobs, runs a container, uploads result,
# then submits completion with a result hash. Replace container execution with your actual workload.

w3 = Web3(Web3.HTTPProvider(RPC_URL))
assert w3.is_connected(), "Cannot connect to RPC"
acct: LocalAccount = Account.from_key(PRIVATE_KEY)

job_manager_abi = [
    {"inputs":[{"internalType":"address","name":"node","type":"address"}],"name":"getRecommendedJobs","outputs":[{"internalType":"uint256[]","name":"recommendedJobs","type":"uint256[]"}],"stateMutability":"view","type":"function"},
    {"inputs":[{"internalType":"uint256","name":"jobId","type":"uint256"},{"internalType":"bytes32","name":"resultHash","type":"bytes32"},{"internalType":"string","name":"resultIpfsHash","type":"string"}],"name":"completeJob","outputs":[],"stateMutability":"nonpayable","type":"function"}
]
job_manager = w3.eth.contract(address=JOB_MANAGER, abi=job_manager_abi)


def run_workload(job_id: int) -> tuple[str, bytes]:
    # Placeholder: simulate a computation and produce an IPFS-like CID and keccak hash
    payload = json.dumps({"jobId": job_id, "timestamp": int(time.time())}).encode()
    # For demo, compute a keccak hash and pretend a CID
    result_hash = w3.keccak(payload)
    cid = f"cid://job-{job_id}-{result_hash.hex()}"
    return cid, result_hash


def send_tx(fn):
    tx = fn.build_transaction({
        'from': acct.address,
        'nonce': w3.eth.get_transaction_count(acct.address),
        'gas': 800_000,
        'maxFeePerGas': w3.to_wei('2', 'gwei'),
        'maxPriorityFeePerGas': w3.to_wei('1', 'gwei'),
        'chainId': w3.eth.chain_id,
    })
    signed = acct.sign_transaction(tx)
    tx_hash = w3.eth.send_raw_transaction(signed.rawTransaction)
    receipt = w3.eth.wait_for_transaction_receipt(tx_hash)
    if receipt.status != 1:
        raise RuntimeError('Transaction failed')
    return receipt


def main():
    print("Provider client started", {"node": NODE_ADDRESS, "chainId": w3.eth.chain_id})
    while True:
        try:
            jobs = job_manager.functions.getRecommendedJobs(NODE_ADDRESS).call()
            for job_id in jobs:
                # Execute containerized workload (placeholder)
                cid, result_hash = run_workload(job_id)
                print(f"Submitting result for job {job_id}")
                send_tx(job_manager.functions.completeJob(int(job_id), result_hash, cid))
        except Exception as e:
            print(f"Loop error: {e}")
        time.sleep(POLL_INTERVAL)


if __name__ == '__main__':
    main()
