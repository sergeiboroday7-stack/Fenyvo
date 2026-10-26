'use strict';

const crypto = require('node:crypto');

const SUPPORT_EMAIL = 'support@fenyvo.com';

function validateTicket({ text, email, consent }) {
  const cleanText = typeof text === 'string' ? text.trim() : '';
  const cleanEmail = typeof email === 'string' ? email.trim() : '';

  if (consent !== true) {
    throw new Error('Подтвердите согласие на передачу обращения');
  }

  if (cleanText.length < 5 || cleanText.length > 2000) {
    throw new Error('Текст обращения должен содержать от 5 до 2000 символов');
  }

  if (
    cleanEmail.length > 254 ||
    !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(cleanEmail)
  ) {
    throw new Error('Укажите корректный email для ответа');
  }

  return { text: cleanText, email: cleanEmail };
}

async function submitSupportTicket({ text, email, consent, ticketId }) {
  const ticket = validateTicket({ text, email, consent });

  const apiKey = process.env.BREVO_API_KEY?.trim();
  if (!apiKey) {
    throw new Error('Служба отправки обращений пока недоступна');
  }

  if (
    typeof ticketId !== 'string' ||
    !/^FEN-[0-9]{13}-[0-9A-F]{12}$/.test(ticketId)
  ) {
    throw new Error('Invalid ticket ID');
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 12000);

  try {
    const response = await fetch('https://api.brevo.com/v3/smtp/email', {
      method: 'POST',
      headers: {
        'api-key': apiKey,
        'Content-Type': 'application/json',
        accept: 'application/json',
      },
      body: JSON.stringify({
        sender: { name: 'Fenyvo Support', email: SUPPORT_EMAIL },
        to: [{ email: SUPPORT_EMAIL }],
        replyTo: { email: ticket.email },
        subject: `Fenyvo Support — обращение ${ticketId}`,
        textContent: [
          `Номер обращения: ${ticketId}`,
          `Контактный email: ${ticket.email}`,
          '',
          'Вопрос пользователя:',
          ticket.text,
        ].join('\n'),
      }),
      signal: controller.signal,
    });

    if (response.status !== 201) {
      throw new Error('Не удалось передать обращение. Попробуйте позже');
    }

    return { ticketId, accepted: true };
  } catch (error) {
    if (error?.name === 'AbortError') {
      throw new Error(
        'Время отправки обращения истекло. Проверьте почту перед повторной попыткой',
      );
    }
    throw error;
  } finally {
    clearTimeout(timeout);
  }
}

module.exports = { validateTicket, submitSupportTicket };
