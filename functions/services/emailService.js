const { Resend } = require("resend");
require("dotenv").config();
const { defineSecret } = require("firebase-functions/params");

const RESEND_API_KEY = defineSecret("RESEND_API_KEY");

/**
 * Helper to send transactional emails via Resend
 *
 * @param {Object} options Email options
 * @param {string|string[]} options.to Recipient email address(es)
 * @param {string} options.subject Email subject
 * @param {string} options.html HTML content of the email
 * @param {string} [options.from="Gatekipa <hello@gatekipa.com>"] Sender email address
 * @returns {Promise<Object>} Response from Resend API or null if disabled
 */
async function sendEmail({ to, subject, html, from = "Gatekipa <hello@gatekipa.com>" }) {
  const secretValue = RESEND_API_KEY.value();
  
  if (!secretValue) {
    console.warn("sendEmail: RESEND_API_KEY is not configured. Email will not be sent.");
    return null;
  }

  const resend = new Resend(secretValue);

  try {
    const response = await resend.emails.send({
      from,
      to,
      subject,
      html,
    });
    
    console.log(`Successfully dispatched email to: ${to}`);
    return response;
  } catch (error) {
    console.error(`Failed to send email to ${to}:`, error);
    throw error;
  }
}

module.exports = {
  sendEmail,
};
