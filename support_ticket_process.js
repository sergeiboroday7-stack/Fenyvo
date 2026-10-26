'use strict';

const store = require('./support_ticket_store');
const { validateTicket, submitSupportTicket } = require('./support_ticket');

async function processTicket(user, requestId, data) {
  if (
    typeof requestId !== 'string' ||
    !/^[a-zA-Z0-9_-]{8,100}$/.test(requestId)
  ) {
    throw new Error('Некорректный идентификатор обращения');
  }

  const ticket = validateTicket(data);
  const existing = store.loadTicket(user, requestId);

  if (existing) {
    return {
      accepted: existing.status === 'accepted',
      ticketId: existing.ticketId || null,
      status: existing.status,
    };
  }

  const created = store.createTicket(user, requestId);
  if (!created.created) {
    const record = created.record;
    return {
      accepted: record.status === 'accepted',
      ticketId: record.ticketId,
      status: record.status,
    };
  }
  store.claimTicket(user, requestId);

  try {
    const result = await submitSupportTicket({
      ...ticket,
      consent: true,
      ticketId: created.record.ticketId,
    });

    store.updateTicket(user, requestId, 'accepted', {
      ticketId: result.ticketId,
    });

    return { ...result, status: 'accepted' };
  } catch (_) {
    store.updateTicket(user, requestId, 'unknown');
    throw new Error(
      'Результат отправки не подтверждён. Не отправляйте повторно.',
    );
  }
}

module.exports = { processTicket };
