const axios = require('axios');
const logger = require('firebase-functions/logger');

/**
 * Classifies a merchant name into one of the default business categories using Gemini 2.5 Flash.
 * Falls back to 'others' if the API is not configured or fails.
 * 
 * @param {string} merchantName - The merchant name
 * @returns {Promise<string>} One of: 'food_groceries', 'utilities', 'transport_travel', 'digital_services', 'entertainment_leisure', 'business_software', 'others'
 */
async function classifyMerchantAI(merchantName) {
  const geminiKey = process.env.GEMINI_API_KEY;
  if (!geminiKey || !merchantName) {
    return 'others';
  }

  const VALID_CATEGORIES = ['food_groceries', 'utilities', 'transport_travel', 'digital_services', 'entertainment_leisure', 'business_software', 'others'];

  try {
    const geminiEndpoint = `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${geminiKey}`;
    const payload = {
      contents: [
        {
          parts: [
            {
              text: `You are an expert financial ledger categorization bot. Classify the following merchant name into exactly one of these categories: ${VALID_CATEGORIES.join(', ')}. 
              Merchant Name: "${merchantName}".
              Respond with ONLY a valid JSON object matching this schema: {"category": "category_name"}`
            }
          ]
        }
      ],
      generationConfig: {
        responseMimeType: "application/json"
      }
    };

    const res = await axios.post(geminiEndpoint, payload, {
      headers: { "Content-Type": "application/json" },
      timeout: 3000
    });

    const responseText = res.data.candidates?.[0]?.content?.parts?.[0]?.text;
    if (responseText) {
      const result = JSON.parse(responseText.trim());
      if (VALID_CATEGORIES.includes(result.category)) {
        logger.info(`[Gemini AI] Classified "${merchantName}" as: ${result.category}`);
        return result.category;
      }
    }
  } catch (error) {
    logger.warn(`[Gemini AI] Classification failed for "${merchantName}": ${error.message}`);
  }

  // Basic fallback heuristics
  const lower = merchantName.toLowerCase();
  if (lower.includes('uber') || lower.includes('bolt') || lower.includes('transport') || lower.includes('airline')) return 'transport_travel';
  if (lower.includes('netflix') || lower.includes('spotify') || lower.includes('youtube')) return 'entertainment_leisure';
  if (lower.includes('aws') || lower.includes('google') || lower.includes('microsoft') || lower.includes('digitalocean')) return 'digital_services';
  if (lower.includes('figma') || lower.includes('canva') || lower.includes('slack') || lower.includes('zoom')) return 'business_software';
  if (lower.includes('supermarket') || lower.includes('food') || lower.includes('groceries')) return 'food_groceries';

  return 'others';
}

/**
 * Generates spending insights and anomalies reports based on user transaction history and subscriptions.
 * 
 * @param {Array} transactions - List of recent transactions
 * @param {Array} subscriptions - List of detected subscriptions
 * @returns {Promise<object>} The insights report object
 */
async function generateSpendingInsightsAI(transactions, subscriptions) {
  const geminiKey = process.env.GEMINI_API_KEY;
  
  const defaultInsights = {
    summary: "Your spending is currently stable. Ensure to monitor card renewals regularly.",
    anomalies: [],
    suggestions: ["Set up a Disposable Card for trial sign-ups to avoid hidden charges."]
  };

  if (!geminiKey) {
    return defaultInsights;
  }

  try {
    const geminiEndpoint = `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${geminiKey}`;
    
    // Format input data to keep tokens low
    const formattedTxns = transactions.slice(0, 15).map(t => ({
      merchant: t.merchant_name || 'Unknown',
      amount: t.amount,
      type: t.type,
      date: t.created_at
    }));

    const formattedSubs = subscriptions.map(s => ({
      name: s.name,
      amount: s.amount ? s.amount / 100 : 0,
      currency: s.currency
    }));

    const payload = {
      contents: [
        {
          parts: [
            {
              text: `You are an elite personal financial advisor and AI spending coach. Analyze this user's recent transaction history and active subscriptions:
              Transactions: ${JSON.stringify(formattedTxns)}
              Subscriptions: ${JSON.stringify(formattedSubs)}
              
              Task:
              1. Write a short, encouraging summary of their spending behavior.
              2. Identify any anomalies (e.g. price hikes, duplicate subscription services, unrecognized merchants, high velocity spending spikes).
              3. Provide actionable suggestions to save money (e.g. locking cards, disabling dormant plans).
              
              Respond with ONLY a valid JSON object matching this schema:
              {
                "summary": "String",
                "anomalies": ["String", "String"],
                "suggestions": ["String", "String"]
              }`
            }
          ]
        }
      ],
      generationConfig: {
        responseMimeType: "application/json"
      }
    };

    const res = await axios.post(geminiEndpoint, payload, {
      headers: { "Content-Type": "application/json" },
      timeout: 5000
    });

    const responseText = res.data.candidates?.[0]?.content?.parts?.[0]?.text;
    if (responseText) {
      const result = JSON.parse(responseText.trim());
      logger.info("[Gemini AI] Successfully generated spending insights");
      return result;
    }
  } catch (error) {
    logger.error("[Gemini AI] Failed to generate spending insights:", error);
  }

  return defaultInsights;
}

module.exports = {
  classifyMerchantAI,
  generateSpendingInsightsAI
};
