import React, { useEffect, useState } from "react";
import { api } from "./api/client";

const styles = {
  container: { fontFamily: "sans-serif", maxWidth: 700, margin: "40px auto", padding: "0 20px" },
  title: { fontSize: 24, marginBottom: 24 },
  form: { display: "flex", gap: 8, marginBottom: 24 },
  input: { flex: 1, padding: "8px 12px", fontSize: 16, border: "1px solid #ccc", borderRadius: 4 },
  button: { padding: "8px 16px", fontSize: 16, cursor: "pointer", borderRadius: 4, border: "none", background: "#0073e6", color: "#fff" },
  deleteBtn: { background: "#e60000", color: "#fff", border: "none", borderRadius: 4, padding: "4px 10px", cursor: "pointer" },
  item: { display: "flex", justifyContent: "space-between", alignItems: "center", padding: "10px 14px", marginBottom: 8, background: "#f5f7fa", borderRadius: 6 },
  error: { color: "red", marginBottom: 12 },
  status: { color: "#666", marginBottom: 12 },
};

export default function App() {
  const [items, setItems] = useState([]);
  const [inputValue, setInputValue] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);

  const loadItems = async () => {
    setLoading(true);
    setError(null);
    try {
      const data = await api.getItems();
      setItems(data);
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadItems();
  }, []);

  const handleCreate = async (e) => {
    e.preventDefault();
    if (!inputValue.trim()) return;
    setError(null);
    try {
      await api.createItem({ name: inputValue.trim() });
      setInputValue("");
      await loadItems();
    } catch (err) {
      setError(err.message);
    }
  };

  const handleDelete = async (id) => {
    setError(null);
    try {
      await api.deleteItem(id);
      await loadItems();
    } catch (err) {
      setError(err.message);
    }
  };

  return (
    <div style={styles.container}>
      <h1 style={styles.title}>Prototype App</h1>
      <form style={styles.form} onSubmit={handleCreate}>
        <input
          style={styles.input}
          type="text"
          placeholder="Enter item name..."
          value={inputValue}
          onChange={(e) => setInputValue(e.target.value)}
        />
        <button style={styles.button} type="submit">Add Item</button>
      </form>
      {error && <p style={styles.error}>⚠️ {error}</p>}
      {loading && <p style={styles.status}>Loading...</p>}
      {!loading && items.length === 0 && <p style={styles.status}>No items yet. Add one above.</p>}
      {items.map((item) => (
        <div key={item.id} style={styles.item}>
          <span>{item.name}</span>
          <button style={styles.deleteBtn} onClick={() => handleDelete(item.id)}>Delete</button>
        </div>
      ))}
    </div>
  );
}