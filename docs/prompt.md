Our goal is to build the simplest AXI4/5 formal VIP that can be used to formally verify SoC IPs such as FIFOs, crossbars/interconnects and DMAs. These IPs are found in ./soc-testbed and IPs from many vendors are abstracted by shared interfaces per role, so we can use it. The formal tool we will use is qverify. Let me know if you cannot run it, or read waveforms from it to analyze if the counterexamples are legit or not.

My vision for the project is along these steps:

1. We have extracted out AXI4/5 rules in csv files, and we have the full AXI4 spec as txt. Check them first.
2. We have implemented most intra-channel rules as SVAs in ./axi_sva/our/*. Anything not there, we want to implement, but follow the same architecture and keep it minimal and concise.
3. To implement inter-channel rules, the problem is tracking a transaction through an IP. 
Here, we run into the FIFO problem. 
AXI allows undefined number of outstanding transactions without any time limit.
We can harden this by setting parameters for max no of outstanding transactions, and max clock cycles for a response.
Let's use the same terms from the spec if possible.
And read responses can be out of order as long as they have different rids.
So, the problem of proving the AXI functionality boils down to proving that an AXI design acts as a FIFO.
A fifo has an input sequence x[n] and an output sequence y[n], and to prove its a fifo, we have to prove x[n] == y[n] and y[i] comes after x[i].
The paper papers/industrial_formal.pdf discusses three ways to prove a fifo.
1. Keep a shadow fifo of all d1s that enter the fifo, and verify thats a fifo.
2. Tracking three transactions: d1, d2, d3 and proving ordering of d1,d2 and uniqueness of d3.
3. Tracking one transaction: keep a counter. Before data d enters the fifo, increment the counter if there's a write, or decrement if there's a read. After d enters, only decrement if there's a read. When counter is 1, compare the output with d.
Counters, scoreboards/shadow FIFOs are expensive in formal, so (2) is preferred.
The key idea is this: many IPs can be viewed as fifos. The IPs take some data x, and output f(x). Both x and f(x) can be "packets" that span several clocks. We choose an arbitary packet x, then at an arbitary time, drive that x (or wait for x to be seen on input), calculate the corresponding f(x). We then monitor the output, comparing each output packet (when done, found by xlast or something) to f(x). and we write the SVA on the register that checks for that equality.
In AXI, there are three FIFOs.
  1. AR -> R. For an arbitarily selected AR (with an arbiary rid) pushed through at an arbitary time, we should prove, there will be a corresponding R matching the AR within the clock cycle limit. For this, we can maybe use the counter-free method (2). Because the legnth, strobe...etc of R carry enough information, that if we prove that for a unique AR, there will be a unique R, we have effectively proved that. One can argue "what if the design gives an R that corresponds to AR in the same order, within a given rid, but duplicates the data (this is caught by uniqueness of d3), or has the same legnth/strobes but wrong data (that's a payload problem proven seperately, using the same tracking infra), or has a very specific bug to mimick this (we can ignore that)"
  2. AW -> W. This is not exactly a fifo, becase AW/W can come at any order. But still we have to prove x[n] == y[n]. This also we can prove with method (2), by maybe relaxing the ordering.
  3. (AW+W) -> B. Now this cant be proven with (2). Because B, the f(x) has no identifiable info. it just has OKAY/ERROR, where all transactions may be OKAY. So, we can use (1) to prove this.
4. We build this cross-channel FIFO tracking infra in `per_role_fvip/fifo/`, and keep it very minimal, concise and readable.
5. We test zipcpu's axi fifo with our fvip and tighten everything to make sure we can prove/disprove that.
6. Once that works, we move to a 2x2 axi crossbar. for the 2 masters, we choose an arbitary mid, and prove the crossbar can route it while adhreing to protocol. Tighten anything else.
7. We scale to prove, say a 6x6 crossbar.
8. We prove a DMA and other IPs.
9. The ultimate goal is to prove most of the IPs in ./soc-testbed, and if some have real bugs, analyze the counterexample trace to create a simple SV tb to recreate the bug to be submitted as PR in their repos.

Now, 5,6,7 may need invariants. I want to avoid writing IP specific invariants if possible, because I want this FVIP to be generalized
