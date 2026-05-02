const API_URL = import.meta.env.VITE_API_URL;

async function request(path, options = {}) {
  const res = await fetch(`${API_URL}${path}`, {
    headers: { "Content-Type": "application/json" },
    ...options,
  });
  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error(err.error || `Request failed: ${res.status}`);
  }
  return res.json();
}

export const api = {
  getItems: () => request("/items"),
  getItem: (id) => request(`/items/${id}`),
  createItem: (data) =>
    request("/items", { method: "POST", body: JSON.stringify(data) }),
  deleteItem: (id) => request(`/items/${id}`, { method: "DELETE" }),
};