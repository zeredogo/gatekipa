const axios = require("axios");
const AES256 = require("aes-everywhere");

(async () => {
  try {
    const token = "at_live_d09dc71e7d180753b794a64c5c294befd0a1af065d12b82824b747cbc4156adf3afac84d012ca68e3d5bf171528197ce200e7a415f7bc2c1505f65b8d571b466d1bb4a629a7e84aa78b2ea804d7b834ab81627836474885ed3ba0724349b4690eb12d9ddfd91b40afe6208c0ef09bddd03aaf2a8879520d31a0d83609718f22ba1d2e5a58c9d8825bf6a4c4a2a5343b4f986305ad099024535e96364471614b500feec1cc82b7c01e3bb456db3493c23b63313bd56422ad1ebc8ceac6a85fd1ee83a17a9ee62407330426017e89393311b75c172e72f49f83a0cb16f73d30cddfdfa0a5317c943956b8c26b330b055a1fcb39e469e2d54b05f0ce2db573c6ff2";
    const secret = "sk_live_VTJGc2RHVmtYMStrdmgzdU1QWHNoRXlTclFSQ0xJK09qWk56UUI3cHlGUVpNYktGL1dmeU5QUEQ4QmxOVlo2T0tuL2Z2Y0dGQ3VldDhtb3RjN3hlRWRva09SWG5mMzRmRHUrM0NZWEN3V0Flak1TczJlNDVNR0xSSEtId29ZTWYwNXdqdHhBOUhwTHAyaERGazNjMXZ1R01XekNLMlRBeXZ1dS9KOVNURW1yNzVSNDRwWUw1a3M1RzFVSzRxMkNzUjhGaHBuSVh1aXFvQXFCMlk4V2dUazFWUGdsY2dWWTYvVnQ0TkZKNGpMSTZ4WFljTzZKR016Z05XUE1RN2c3bVQ2MStXaHp2bkx5bnEzUEdDOU56ZldmdmtxSkF1TTdXTXdvOTZ1SXh0SWYxN1IrS2RvblhoTytOS1NxNTRROHowQUlEQWJieDQ2Z2lrSzJGMnRsWkhSZGpuc3JSdFRSVnNZNEgwOEVLTVdDZ1NZVFJITXpXdzN2dGlNOEVpVDhmZ0NRak5aYmgrM2hxbThHN25sVlVvMzVRQXFkRjRxSXVRNGRldytYeXI1WlV1alZlZ0N3T0xlOFBoV2ZTR2hEaENUM0lrTGxmbWI5Z3QwaURwZithTW5wajQ1MGliUDhVajAzVEhvWUgwZ1E9";

    const client = axios.create({
      baseURL: "https://issuecards.api.bridgecard.co/v1/issuing",
      headers: {
        "Content-Type": "application/json",
        "token": `Bearer ${token}`
      }
    });

    const encryptedPin = AES256.encrypt("1234", secret);

    const payload = {
      cardholder_id: "5d83c6278c43414b99c48fe266aa744f",
      card_type: "virtual",
      card_brand: "Visa",
      card_currency: "NGN",
      pin: encryptedPin
    };
    
    const res = await client.post("/cards/create_card", payload);
    console.log("Success Visa NGN:", JSON.stringify(res.data, null, 2));
  } catch (err) {
    if (err.response) {
       console.error("Error Response Status:", err.response.status);
       console.error("Error Response Data:", JSON.stringify(err.response.data, null, 2));
    } else {
       console.error("Error:", err.message);
    }
  }
})();
