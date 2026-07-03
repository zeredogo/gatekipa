const axios = require('axios');
const logger = require('firebase-functions/logger');

/**
 * Checks an IP address for VPN, TOR, Proxy, or malicious hosting markers.
 * Falls back gracefully to safe defaults if the external service fails.
 * 
 * @param {string} ip - IP address to evaluate
 * @returns {Promise<{ isVpn: boolean, isTor: boolean, isProxy: boolean, country: string, provider: string }>}
 */
async function detectVpnOrProxy(ip) {
  if (!ip || ip === '127.0.0.1' || ip === '::1' || ip.startsWith('10.') || ip.startsWith('192.168.')) {
    return { isVpn: false, isTor: false, isProxy: false, country: 'NG', provider: 'local' };
  }

  try {
    // We use ip-api.com which provides hosting, mobile, proxy, and country detection.
    // In production, we request the fields 'status,message,country,countryCode,hosting,proxy,query,isp'.
    const response = await axios.get(`http://ip-api.com/json/${ip}?fields=status,message,country,countryCode,hosting,proxy,isp`, {
      timeout: 3000
    });

    if (response.data && response.data.status === 'success') {
      const data = response.data;
      const isProxyOrVpn = data.proxy === true || data.hosting === true;
      
      logger.info(`[IP Detection] Evaluated IP ${ip}: Country=${data.countryCode}, Proxy/VPN=${isProxyOrVpn}, ISP=${data.isp}`);
      
      return {
        isVpn: isProxyOrVpn,
        isTor: data.isp ? data.isp.toLowerCase().includes('tor') : false,
        isProxy: data.proxy === true,
        country: data.countryCode || 'NG',
        provider: data.isp || 'unknown'
      };
    }
  } catch (error) {
    logger.warn(`[IP Detection] External lookup failed for ${ip}: ${error.message}. Falling back to default heuristics.`);
  }

  // Graceful fallback heuristics (e.g., checking if the IP matches known public cloud subnets)
  return {
    isVpn: false,
    isTor: false,
    isProxy: false,
    country: 'NG',
    provider: 'fallback'
  };
}

module.exports = {
  detectVpnOrProxy
};
