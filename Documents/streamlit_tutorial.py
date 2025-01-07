import streamlit as st
import pandas as pd
import matplotlib.pyplot as plt

st.header("Streamlit Tutorial")

st.write("This is streamlit's swiss-army knife tool")

"You can write teext using magic"

st.markdown("# Largest header")
st.markdown("## Medium Header")
st.markdown("Normal size text")

our_data = pd.DataFrame({
    'Alex': [4,8,15,16,23,42],
    'Erin': [2,4,8,16,32,64],
    'Irene': [4,18,9,25,99,2]
})

st.write(our_data)
st.table(our_data)
st.dataframe(our_data.style.highlight_max(axis=1))

st.header("Plotting")

st.line_chart(our_data)

our_fig=plt.figure()
plt.plot(our_data['Alex'])
st.pyplot(our_fig)

st.header("There are widgets")

x=st.slider('The value of x', min_value=1, max_value=50)
st.write('The value of', x, 'squared is', x**2)

plot_choice=st.selectbox("Whose dataset do you want to plot?", ('Alex','Erin','Irene'))

selection_fig = plt.figure()
plt.plot(our_data[plot_choice])
plt.title(f'This is {plot_choice}\'s data set')
st.pyplot(selection_fig)
